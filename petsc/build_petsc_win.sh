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
CYGWIN_LIBRARY_PREFIX="${CYGWIN_PREFIX}/Library"

if [[ "${scalar}" == "complex" ]]; then
    with_hypre=0
else
    with_hypre=1
fi

python3 ./configure \
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
    --with-mpi-include="${CYGWIN_LIBRARY_PREFIX}/include" \
    --with-mpi-lib="${CYGWIN_LIBRARY_PREFIX}/lib/msmpi.lib" \
    --with-blaslapack-lib="${CYGWIN_LIBRARY_PREFIX}/lib/mkl_rt.lib" \
    --with-blaslapack-include="${CYGWIN_LIBRARY_PREFIX}/include" \
    --with-mkl_pardiso=1 \
    --with-mkl_pardiso-lib="${CYGWIN_LIBRARY_PREFIX}/lib/mkl_rt.lib" \
    --with-mkl_pardiso-include="${CYGWIN_LIBRARY_PREFIX}/include" \
    --with-hypre=${with_hypre} \
    --with-hypre-include="${CYGWIN_LIBRARY_PREFIX}/include" \
    --with-hypre-lib="${CYGWIN_LIBRARY_PREFIX}/lib/HYPRE.lib" \
    --with-make-exec=/usr/bin/make \
    --ignore-cygwin-link \
    --prefix="${CYGWIN_LIBRARY_PREFIX}"

# --- Post-configure fixups ---

# Remove /usr/bin/python3 references (Cygwin python, not conda python)
sed -i "s%/usr/bin/python3%python%g" $PETSC_ARCH/include/petscconf.h
sed -i "s%/usr/bin/python3%python%g" $PETSC_ARCH/lib/petsc/conf/petscvariables

# Replace absolute Cygwin install prefix path with ${PREFIX} in headers
for f in $PETSC_ARCH/include/petsc*.h; do
    if grep -q "${CYGWIN_LIBRARY_PREFIX}" "$f"; then
        echo "Fixing ${CYGWIN_LIBRARY_PREFIX} in $f"
        sed -i "s%${CYGWIN_LIBRARY_PREFIX}%\${PREFIX}%g" "$f"
    fi
done

# Also fix Windows-style paths in petscconf.h (C:\\Users\\... form)
# Convert install prefix to Windows backslash form for matching
WIN_PREFIX_ESCAPED=$(cygpath -w "$CYGWIN_LIBRARY_PREFIX" | sed 's/\\/\\\\/g')
if [ -n "$WIN_PREFIX_ESCAPED" ]; then
    sed -i "s%${WIN_PREFIX_ESCAPED}%\\\${PREFIX}%g" $PETSC_ARCH/include/petscconf.h
fi

# Also fix Windows forward-slash paths (C:/Users/... form used in wPETSC_DIR)
WIN_PREFIX_FWD=$(cygpath -m "$CYGWIN_LIBRARY_PREFIX")
if [ -n "$WIN_PREFIX_FWD" ]; then
    sed -i "s%${WIN_PREFIX_FWD}%\${PREFIX}%g" $PETSC_ARCH/lib/petsc/conf/petscvariables
fi

# Fix SRC_DIR/work paths (win32fe compiler wrapper references)
for f in $PETSC_ARCH/include/petsc*.h; do
    if grep -q "${CYGWIN_WORK}" "$f"; then
        echo "Fixing ${CYGWIN_WORK} in $f"
        sed -i "s%${CYGWIN_WORK}%\${PREFIX}%g" "$f"
    fi
done

# --- Build and install ---
make MAKE_NP=${CPU_COUNT}
make install

# Fix ${prefix} (unexpanded Makefile var) → ${wPETSC_DIR} in installed petscvariables.
# petsc4py on Windows only resolves ${wPETSC_DIR}, not ${prefix}, so external lib paths
# like ${prefix}/lib/msmpi.lib would expand to /lib/msmpi.lib (broken).
sed -i "s%\${prefix}%\${wPETSC_DIR}%g" "${CYGWIN_LIBRARY_PREFIX}/lib/petsc/conf/petscvariables"

# --- Post-install path fixups for Windows native tool compatibility ---
# The installed config files still contain Cygwin-style paths from the build.
# Convert them so downstream consumers (petsc4py, pkg-config, etc.) work natively.

# Replace Cygwin install-prefix paths in config files
# Use ${wPETSC_DIR} for Makefile-parsed files, ${prefix} for pkg-config files
for conf_file in "${CYGWIN_LIBRARY_PREFIX}/lib/petsc/conf/petscvariables" \
                 "${CYGWIN_LIBRARY_PREFIX}/lib/petsc/conf/variables"; do
    if [ -f "$conf_file" ]; then
        echo "Fixing Cygwin paths in $conf_file"
        sed -i "s%${CYGWIN_LIBRARY_PREFIX}%\${wPETSC_DIR}%g" "$conf_file"
    fi
done
if [ -f "${CYGWIN_LIBRARY_PREFIX}/lib/pkgconfig/PETSc.pc" ]; then
    echo "Fixing Cygwin paths in PETSc.pc"
    sed -i "s%${CYGWIN_LIBRARY_PREFIX}%\${prefix}%g" "${CYGWIN_LIBRARY_PREFIX}/lib/pkgconfig/PETSc.pc"
fi

# Replace Cygwin tool paths with generic names (not available outside Cygwin)
sed -i \
    -e 's%/usr/bin/make%make%g' \
    -e 's%/usr/bin/bash%bash%g' \
    -e 's%/usr/bin/sed%sed%g' \
    -e 's%/usr/bin/mkdir -p%mkdir%g' \
    -e 's%/usr/bin/mv%mv%g' \
    -e 's%/usr/bin/cp%cp%g' \
    -e 's%/usr/bin/grep%grep%g' \
    -e 's%/usr/bin/rm%rm%g' \
    -e 's%/usr/bin/diff%diff%g' \
    -e 's%/usr/bin/true%true%g' \
    "${CYGWIN_LIBRARY_PREFIX}/lib/petsc/conf/petscvariables"

# Fix PETSC_DIR in installed petscconf.h (contains hardcoded build-time path)
WIN_LIBRARY_PREFIX=$(python3 -c "
import re
p = '${CYGWIN_LIBRARY_PREFIX}'
m = re.match(r'/cygdrive/([a-zA-Z])/(.*)', p)
if m:
    print(m.group(1).upper() + ':\\\\\\\\' + m.group(2).replace('/', '\\\\\\\\'))
else:
    print(p.replace('/', '\\\\\\\\'))
")
if [ -n "$WIN_LIBRARY_PREFIX" ] && [ -f "${CYGWIN_LIBRARY_PREFIX}/include/petscconf.h" ]; then
    echo "Fixing PETSC_DIR in installed petscconf.h"
    sed -i "s%${WIN_LIBRARY_PREFIX}%\\\${PREFIX}%g" "${CYGWIN_LIBRARY_PREFIX}/include/petscconf.h"
fi

# Remove all Cygwin symlinks in the work directory that rattler-build cannot handle
# PETSc creates various symlinks (configure.log, make.log, RDict.db, etc.)
# whose Cygwin reparse points are unsupported on native Windows
find . -maxdepth 1 -type l -delete

# --- Post-install cleanup ---

# Remove configure hash and pyc files
rm -f ${CYGWIN_LIBRARY_PREFIX}/lib/petsc/conf/configure-hash
find ${CYGWIN_LIBRARY_PREFIX}/lib/petsc -name '*.pyc' -delete

# Strip non-deterministic content (timestamps, machine info)
if [ -f "${CYGWIN_LIBRARY_PREFIX}/include/petscmachineinfo.h" ]; then
    echo "Stripping petscmachineinfo.h"
    echo 'static const char *petscmachineinfo = "";' > "${CYGWIN_LIBRARY_PREFIX}/include/petscmachineinfo.h"
fi
if [ -f "${CYGWIN_LIBRARY_PREFIX}/include/petscconfiginfo.h" ]; then
    echo "Stripping petscconfiginfo.h"
    echo 'static const char *petscconfigureruntime = "";' > "${CYGWIN_LIBRARY_PREFIX}/include/petscconfiginfo.h"
fi

# Remove reconfigure script (contains build-specific paths and timestamps)
rm -f ${CYGWIN_LIBRARY_PREFIX}/lib/petsc/conf/reconfigure-*.py

# Fix build prefix references in installed files
# First strip win32fe wrapper paths to just the tool name
for f in $(grep -rl "${CYGWIN_WORK}" "${CYGWIN_LIBRARY_PREFIX}/lib/petsc" 2>/dev/null) "${CYGWIN_LIBRARY_PREFIX}/lib/pkgconfig/PETSc.pc"; do
    if [ -f "$f" ]; then
        echo "Fixing work dir in $f"
        sed -i "s%${CYGWIN_WORK}/lib/petsc/bin/win32fe/%%g" "$f"
        sed -i "s%${CYGWIN_WORK}%\${PREFIX}%g" "$f"
    fi
done

# Create petsc.lib alias for libpetsc.lib
# PETSc builds as libpetsc.lib (Unix convention) but setuptools on Windows
# converts -lpetsc to petsc.lib when linking
if [ -f "${CYGWIN_LIBRARY_PREFIX}/lib/libpetsc.lib" ] && [ ! -f "${CYGWIN_LIBRARY_PREFIX}/lib/petsc.lib" ]; then
    cp "${CYGWIN_LIBRARY_PREFIX}/lib/libpetsc.lib" "${CYGWIN_LIBRARY_PREFIX}/lib/petsc.lib"
fi

# Move libpetsc.dll from lib/ to bin/ (conda-forge convention)
# On Windows, DLLs must be in Library/bin/ which is on PATH at runtime.
# PETSc's make install uses Unix convention and puts DLLs in lib/.
if [ -f "${CYGWIN_LIBRARY_PREFIX}/lib/libpetsc.dll" ]; then
    mv "${CYGWIN_LIBRARY_PREFIX}/lib/libpetsc.dll" "${CYGWIN_LIBRARY_PREFIX}/bin/libpetsc.dll"
fi

# Remove example and data files
rm -fr ${CYGWIN_LIBRARY_PREFIX}/share/petsc/examples/src
rm -fr ${CYGWIN_LIBRARY_PREFIX}/share/petsc/datafiles
