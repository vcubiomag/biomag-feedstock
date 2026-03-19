#!/bin/bash
set -ex

# =============================================================================
# PETSc Windows Build Script (runs under Cygwin)
#
# This script is invoked by build_petsc.bat under Cygwin bash.
# Cygwin provides the Unix environment required by PETSc's configure script.
# The actual compilation uses native Windows compilers via PETSc's win32fe
# wrappers, so the output .lib/.dll files have zero Cygwin dependency.
# =============================================================================

# --- Path conversion ---------------------------------------------------------
# rattler-build sets env vars in Windows format (C:\...). Convert to Cygwin
# paths for configure, and save originals for post-processing sed replacements.

# Ensure Cygwin utilities are available before anything else
export PATH="/usr/bin:$PATH"

env | grep -i "user"

exit



# Source the environment file written by build_petsc.bat.
# Cygwin bash does not reliably inherit Windows environment variables, so the
# bat file exports them to _build_env.sh in the working directory.
_env_file="$(pwd)/_build_env.sh"
if [ -f "$_env_file" ]; then
    # Strip Windows carriage returns before sourcing
    sed -i 's/\r$//' "$_env_file"
    source "$_env_file"
else
    echo "WARNING: $_env_file not found, relying on inherited environment"
fi

# Save Windows-format paths before conversion
WIN_SRC_DIR="$SRC_DIR"
WIN_PREFIX="$PREFIX"
WIN_LIBRARY_PREFIX="$LIBRARY_PREFIX"
WIN_BUILD_PREFIX="$BUILD_PREFIX"

# Convert to Cygwin paths
# Note: avoid cygpath -ms (short 8.3 names) as PETSc configure compares
# PETSC_DIR against os.getcwd() which returns long paths — they must match.
export SRC_DIR=$(cygpath -u "$SRC_DIR")
export PREFIX=$(cygpath -u "$PREFIX")
export LIBRARY_PREFIX=$(cygpath -u "$LIBRARY_PREFIX")
export BUILD_PREFIX=$(cygpath -u "$BUILD_PREFIX")
export RECIPE_DIR=$(cygpath -u "$RECIPE_DIR")

# Mixed paths (C:/...) — PETSc may also write paths in this format
MIX_BUILD_PREFIX=$(cygpath -m "$WIN_BUILD_PREFIX")
MIX_LIBRARY_PREFIX=$(cygpath -m "$WIN_LIBRARY_PREFIX")

# --- PATH setup --------------------------------------------------------------
# Prepend PETSc win32fe directory so configure can find win32fe wrappers
# Keep the inherited Windows PATH for native compilers and conda build tools
export PATH="/usr/bin:$SRC_DIR/lib/petsc/bin/win32fe:$PATH"

# Restore Windows compiler environment variables (LIB, INCLUDE) so that
# MSVC's link.exe and Intel's ifx can find runtime libraries like ifconsol.lib.
# Replace any unexpanded %PREFIX% / %BUILD_PREFIX% references with actual values.
if [ -n "$WIN_LIB" ]; then
    WIN_LIB="${WIN_LIB//'%PREFIX%'/$WIN_PREFIX}"
    WIN_LIB="${WIN_LIB//'%BUILD_PREFIX%'/$WIN_BUILD_PREFIX}"
    export LIB="$WIN_LIB"
fi
if [ -n "$WIN_INCLUDE" ]; then
    WIN_INCLUDE="${WIN_INCLUDE//'%PREFIX%'/$WIN_PREFIX}"
    WIN_INCLUDE="${WIN_INCLUDE//'%BUILD_PREFIX%'/$WIN_BUILD_PREFIX}"
    export INCLUDE="$WIN_INCLUDE"
fi

# Find Intel Fortran runtime libraries (ifconsol.lib) and add to LIB.
# The ifx conda package may place these in the build prefix or elsewhere.
IFX_LIB_DIR=""
for search_dir in "$WIN_BUILD_PREFIX" "$WIN_PREFIX" "C:\\Program Files (x86)\\Intel\\oneAPI"; do
    found=$(find "$(cygpath -u "$search_dir")" -name "ifconsol.lib" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        IFX_LIB_DIR=$(cygpath -w "$(dirname "$found")")
        break
    fi
done
if [ -n "$IFX_LIB_DIR" ]; then
    echo "Found Intel Fortran libraries at: $IFX_LIB_DIR"
    export LIB="${LIB};${IFX_LIB_DIR}"
else
    echo "WARNING: ifconsol.lib not found — Fortran linking may fail"
fi

# Hide Cygwin's link which conflicts with MSVC's link.exe (the linker).
# Cygwin's link is a Unix hard-link utility whose output causes PETSc's
# compiler checks to fail. Rename it so MSVC's linker is found instead.
for f in /usr/bin/link /usr/bin/link.exe; do
    if [ -f "$f" ]; then
        mv "$f" "${f}.cygwin"
    fi
done

# --- Configure ---------------------------------------------------------------
export PETSC_DIR=$SRC_DIR
export PETSC_ARCH=arch-conda-c-opt

# Hypre is only available for real scalar type
with_hypre=1
if [[ "${scalar}" == "complex" ]]; then
    with_hypre=0
fi

# Use Cygwin python to run PETSc configure.
# PETSc's chkcygwinwindowscompilers() auto-expands --with-cc=cl to the full
# win32fe_cl path. The --ignore-cygwin-link flag avoids the Cygwin link.exe
# vs MSVC link.exe conflict check.
/usr/bin/python3 ./configure \
    --with-cc=cl \
    --with-cxx=cl \
    --with-fc=ifx \
    --with-fortran-bindings=0 \
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
    --with-openmp=1 \
    --with-blaslapack-dir=${LIBRARY_PREFIX} \
    --with-mkl_pardiso=1 \
    --with-yaml=1 \
    --with-hwloc=1 \
    --with-hypre=${with_hypre} \
    --with-metis=1 \
    --with-ptscotch=1 \
    --with-suitesparse=1 \
    --with-suitesparse-dir=${LIBRARY_PREFIX} \
    --with-hdf5=0 \
    --with-fftw=0 \
    --with-parmetis=0 \
    --with-scalapack=0 \
    --with-mumps=0 \
    --with-superlu=0 \
    --with-superlu_dist=0 \
    --with-cuda=0 \
    --with-make-exec=/usr/bin/make \
    --ignore-cygwin-link \
    --prefix=${LIBRARY_PREFIX} || (cat configure.log && exit 1)

# --- Build -------------------------------------------------------------------
make MAKE_NP=${CPU_COUNT}
make install

# --- Post-processing ---------------------------------------------------------
# Clean up build artifacts and strip non-deterministic content to ensure
# reproducible package hashes across builds.

rm -f ${LIBRARY_PREFIX}/lib/petsc/conf/configure-hash
find ${LIBRARY_PREFIX}/lib/petsc -name '*.pyc' -delete

# Strip non-deterministic content (timestamps, machine info) from headers
if [ -f "${LIBRARY_PREFIX}/include/petscmachineinfo.h" ]; then
    echo "Stripping petscmachineinfo.h"
    echo 'static const char *petscmachineinfo = "";' > "${LIBRARY_PREFIX}/include/petscmachineinfo.h"
fi
if [ -f "${LIBRARY_PREFIX}/include/petscconfiginfo.h" ]; then
    echo "Stripping petscconfiginfo.h"
    echo 'static const char *petscconfigureruntime = "";' > "${LIBRARY_PREFIX}/include/petscconfiginfo.h"
fi

# Remove reconfigure scripts (contain build-specific paths and timestamps)
rm -f ${LIBRARY_PREFIX}/lib/petsc/conf/reconfigure-*.py

# Replace build prefix references in installed files.
# PETSc configure under Cygwin may write paths in Cygwin (/cygdrive/c/...),
# mixed (C:/...), or Windows (C:\...) format. Handle all variants.
for f in $(grep -rle "${BUILD_PREFIX}\|${MIX_BUILD_PREFIX}" "${LIBRARY_PREFIX}/lib/petsc" 2>/dev/null) \
         "${LIBRARY_PREFIX}/lib/pkgconfig/PETSc.pc"; do
    [ -f "$f" ] || continue
    echo "Fixing build prefix references in $f"
    sed -i'' \
        -e "s|${BUILD_PREFIX}/Library/bin/||g" \
        -e "s|${MIX_BUILD_PREFIX}/Library/bin/||g" \
        -e "s|${BUILD_PREFIX}|${LIBRARY_PREFIX}|g" \
        -e "s|${MIX_BUILD_PREFIX}|${MIX_LIBRARY_PREFIX}|g" \
        "$f"
done

# Fix build prefix references in headers
for f in $(grep -rle "${BUILD_PREFIX}\|${MIX_BUILD_PREFIX}" "${LIBRARY_PREFIX}/include" 2>/dev/null); do
    echo "Fixing build prefix in header $f"
    sed -i'' \
        -e "s|${BUILD_PREFIX}|${LIBRARY_PREFIX}|g" \
        -e "s|${MIX_BUILD_PREFIX}|${MIX_LIBRARY_PREFIX}|g" \
        "$f"
done

# Remove example and data files
echo "Removing example files"
rm -rf ${LIBRARY_PREFIX}/share/petsc/examples/src
echo "Removing data files"
rm -rf ${LIBRARY_PREFIX}/share/petsc/datafiles
