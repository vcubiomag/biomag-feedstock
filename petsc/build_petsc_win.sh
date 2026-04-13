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

# --- Build and install ---
make MAKE_NP=${CPU_COUNT}
make install

# Remove /usr/bin/python3 references (Cygwin python, not conda python)
sed -i "s%/usr/bin/python3%python%g" $CYGWIN_LIBRARY_PREFIX/include/petscconf.h
sed -i "s%/usr/bin/python3%python%g" $CYGWIN_LIBRARY_PREFIX/lib/petsc/conf/petscvariables

# Collapse double-backslash escapes to forward slashes for rattler-build detection
sed -i 's|\\\\|/|g' "$CYGWIN_LIBRARY_PREFIX/include/petscconf.h"

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

for f in $(grep -rlI "${CYGWIN_WORK}/lib/petsc/bin/win32fe/" "${CYGWIN_LIBRARY_PREFIX}/lib/petsc" 2>/dev/null) "${CYGWIN_LIBRARY_PREFIX}/lib/pkgconfig/PETSc.pc"; do
    if [ -f "$f" ]; then
        echo "Fixing win32fe wrapper paths in $f"
        grep "${CYGWIN_WORK}/lib/petsc/bin/win32fe/" "$f" || true
        sed -i "s%${CYGWIN_WORK}/lib/petsc/bin/win32fe/%%g" "$f"
    fi
done

for f in $(grep -rlI "${CYGWIN_WORK}" "${CYGWIN_LIBRARY_PREFIX}/lib/petsc" 2>/dev/null) "${CYGWIN_LIBRARY_PREFIX}/lib/pkgconfig/PETSc.pc"; do
    if [ -f "$f" ]; then
        echo "Fixing work dir in $f"
        grep "${CYGWIN_WORK}" "$f" || true
        sed -i "s%${CYGWIN_WORK}%${CYGWIN_LIBRARY_PREFIX}%g" "$f"
    fi
done

# Convert all Cygwin paths to Windows forward-slash paths so rattler-build
# can detect the prefix and insert relocatable placeholders.
WIN_PREFIX=$(cygpath -m "$PREFIX")
WIN_LIBRARY_PREFIX="${WIN_PREFIX}/Library"
for f in $(grep -rlI "${CYGWIN_PREFIX}" "${CYGWIN_LIBRARY_PREFIX}" 2>/dev/null); do
    if [ -f "$f" ]; then
        echo "Fixing Cygwin paths in $f"
        sed -i \
            -e "s%${CYGWIN_LIBRARY_PREFIX}%${WIN_LIBRARY_PREFIX}%g" \
            -e "s%${CYGWIN_PREFIX}%${WIN_PREFIX}%g" \
            -e 's%/usr/bin/%%g' \
            "$f"
    fi
done

# Replace hardcoded Visual Studio cmake path with bare cmake
sed -i 's%CMAKE = .*cmake.*%CMAKE = cmake%' "$CYGWIN_LIBRARY_PREFIX/lib/petsc/conf/petscvariables"

# Convert wPETSC_DIR backslashes to forward slashes for rattler-build detection
sed -i '/^wPETSC_DIR =/s|\\|/|g' "$CYGWIN_LIBRARY_PREFIX/lib/petsc/conf/petscvariables"

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
