#!/bin/bash
set -ex

export PATH="/usr/bin:$PATH"

export PETSC_ARCH=arch-conda-c-opt

# Derive Cygwin-style paths if not already set
if [ -z "$CYGWIN_PREFIX" ]; then
    CYGWIN_PREFIX=$(cygpath -u "$PREFIX")
fi
CYGWIN_WORK=$(cygpath -u "$SRC_DIR" 2>/dev/null || echo "$PWD")

# On Windows conda, C/C++ libraries install under %PREFIX%\Library
INSTALL_PREFIX="${CYGWIN_PREFIX}/Library"

if [[ "${scalar}" == "complex" ]]; then
    with_hypre=0
else
    with_hypre=1
fi

/usr/bin/python3 ./configure \
    --with-cc=cl \
    --with-cxx=cl \
    --with-fc=0 \
    --COPTFLAGS="-O2" \
    --CXXOPTFLAGS="-O2" \
    --FOPTFLAGS="-O2" \
    --with-clib-autodetect=0 \
    --with-cxxlib-autodetect=0 \
    --with-fortranlib-autodetect=0 \
    --with-debugging=0 \
    --with-shared-libraries=1 \
    --with-ssl=0 \
    --with-x=0 \
    --with-scalar-type=${scalar} \
    --with-mpi=1 \
    --with-mpi-include="${CYGWIN_PREFIX}/Library/include" \
    --with-mpi-lib="${CYGWIN_PREFIX}/Library/lib/msmpi.lib" \
    --with-blaslapack-lib="${CYGWIN_PREFIX}/Library/lib/mkl_rt.lib" \
    --with-blaslapack-include="${CYGWIN_PREFIX}/Library/include" \
    --with-mkl_pardiso=1 \
    --with-mkl_pardiso-lib="${CYGWIN_PREFIX}/Library/lib/mkl_rt.lib" \
    --with-mkl_pardiso-include="${CYGWIN_PREFIX}/Library/include" \
    --with-hypre=${with_hypre} \
    --with-hypre-include="${CYGWIN_PREFIX}/Library/include" \
    --with-hypre-lib="${CYGWIN_PREFIX}/Library/lib/HYPRE.lib" \
    --with-make-exec=/usr/bin/make \
    --ignore-cygwin-link \
    --prefix="${INSTALL_PREFIX}"

# --- Post-configure fixups ---

# Remove /usr/bin/python3 references (Cygwin python, not conda python)
/usr/bin/sed -i "s%/usr/bin/python3%python%g" $PETSC_ARCH/include/petscconf.h
/usr/bin/sed -i "s%/usr/bin/python3%python%g" $PETSC_ARCH/lib/petsc/conf/petscvariables

# Replace absolute Cygwin install prefix path with ${PREFIX} in headers
for f in $PETSC_ARCH/include/petsc*.h; do
    if /usr/bin/grep -q "${INSTALL_PREFIX}" "$f"; then
        echo "Fixing ${INSTALL_PREFIX} in $f"
        /usr/bin/sed -i "s%${INSTALL_PREFIX}%\${PREFIX}%g" "$f"
    fi
done

# Also fix Windows-style paths in petscconf.h (C:\\Users\\... form)
# Convert install prefix to Windows backslash form for matching
WIN_PREFIX_ESCAPED=$(/usr/bin/python3 -c "
import sys, re
p = '${INSTALL_PREFIX}'
# /cygdrive/c/... -> C:\\\\...
m = re.match(r'/cygdrive/([a-zA-Z])/(.*)', p)
if m:
    print(m.group(1).upper() + ':\\\\\\\\' + m.group(2).replace('/', '\\\\\\\\'))
else:
    print(p.replace('/', '\\\\\\\\'))
")
if [ -n "$WIN_PREFIX_ESCAPED" ]; then
    /usr/bin/sed -i "s%${WIN_PREFIX_ESCAPED}%\\\${PREFIX}%g" $PETSC_ARCH/include/petscconf.h
fi

# Also fix Windows forward-slash paths (C:/Users/... form used in wPETSC_DIR)
WIN_PREFIX_FWD=$(/usr/bin/python3 -c "
import re
p = '${INSTALL_PREFIX}'
m = re.match(r'/cygdrive/([a-zA-Z])/(.*)', p)
if m:
    print(m.group(1).upper() + ':/' + m.group(2))
else:
    print(p)
")
if [ -n "$WIN_PREFIX_FWD" ]; then
    /usr/bin/sed -i "s%${WIN_PREFIX_FWD}%\${PREFIX}%g" $PETSC_ARCH/lib/petsc/conf/petscvariables
fi

# Fix SRC_DIR/work paths (win32fe compiler wrapper references)
for f in $PETSC_ARCH/include/petsc*.h; do
    if /usr/bin/grep -q "${CYGWIN_WORK}" "$f"; then
        echo "Fixing ${CYGWIN_WORK} in $f"
        /usr/bin/sed -i "s%${CYGWIN_WORK}%\${PREFIX}%g" "$f"
    fi
done

# --- Build and install ---
/usr/bin/make MAKE_NP=${CPU_COUNT}
/usr/bin/make install

# Fix ${prefix} (unexpanded Makefile var) → ${wPETSC_DIR} in installed petscvariables.
# petsc4py on Windows only resolves ${wPETSC_DIR}, not ${prefix}, so external lib paths
# like ${prefix}/lib/msmpi.lib would expand to /lib/msmpi.lib (broken).
/usr/bin/sed -i "s%\${prefix}%\${wPETSC_DIR}%g" "${INSTALL_PREFIX}/lib/petsc/conf/petscvariables"

# Remove all Cygwin symlinks in the work directory that rattler-build cannot handle
# PETSc creates various symlinks (configure.log, make.log, RDict.db, etc.)
# whose Cygwin reparse points are unsupported on native Windows
/usr/bin/find . -maxdepth 1 -type l -delete

# --- Post-install cleanup ---

# Remove configure hash and pyc files
rm -f ${INSTALL_PREFIX}/lib/petsc/conf/configure-hash
/usr/bin/find ${INSTALL_PREFIX}/lib/petsc -name '*.pyc' -delete

# Strip non-deterministic content (timestamps, machine info)
if [ -f "${INSTALL_PREFIX}/include/petscmachineinfo.h" ]; then
    echo "Stripping petscmachineinfo.h"
    echo 'static const char *petscmachineinfo = "";' > "${INSTALL_PREFIX}/include/petscmachineinfo.h"
fi
if [ -f "${INSTALL_PREFIX}/include/petscconfiginfo.h" ]; then
    echo "Stripping petscconfiginfo.h"
    echo 'static const char *petscconfigureruntime = "";' > "${INSTALL_PREFIX}/include/petscconfiginfo.h"
fi

# Remove reconfigure script (contains build-specific paths and timestamps)
rm -f ${INSTALL_PREFIX}/lib/petsc/conf/reconfigure-*.py

# Fix build prefix references in installed files
# First strip win32fe wrapper paths to just the tool name
for f in $(/usr/bin/grep -rl "${CYGWIN_WORK}" "${INSTALL_PREFIX}/lib/petsc" 2>/dev/null) "${INSTALL_PREFIX}/lib/pkgconfig/PETSc.pc"; do
    if [ -f "$f" ]; then
        echo "Fixing work dir in $f"
        /usr/bin/sed -i "s%${CYGWIN_WORK}/lib/petsc/bin/win32fe/%%g" "$f"
        /usr/bin/sed -i "s%${CYGWIN_WORK}%\${PREFIX}%g" "$f"
    fi
done

# Create petsc.lib alias for libpetsc.lib
# PETSc builds as libpetsc.lib (Unix convention) but setuptools on Windows
# converts -lpetsc to petsc.lib when linking
if [ -f "${INSTALL_PREFIX}/lib/libpetsc.lib" ] && [ ! -f "${INSTALL_PREFIX}/lib/petsc.lib" ]; then
    /usr/bin/cp "${INSTALL_PREFIX}/lib/libpetsc.lib" "${INSTALL_PREFIX}/lib/petsc.lib"
fi

# Remove example and data files
rm -fr ${INSTALL_PREFIX}/share/petsc/examples/src
rm -fr ${INSTALL_PREFIX}/share/petsc/datafiles
