#!/bin/bash
set -ex

# =============================================================================
# PETSc Windows Build Script (runs under Cygwin)
#
# Invoked by build_petsc.bat under Cygwin bash. Cygwin provides the Unix
# environment PETSc's configure requires. Actual compilation uses native
# Windows compilers via PETSc's win32fe wrappers, so the output DLLs/LIBs
# have zero Cygwin runtime dependency.
# =============================================================================

# --- Environment capture -----------------------------------------------------
# Cygwin inherits Windows env vars from the parent cmd.exe process.
# Save Windows-format values before any conversion -- needed for post-install
# sed replacements that must match paths as PETSc wrote them.

export PATH="/usr/bin:$PATH"

WIN_SRC_DIR="$SRC_DIR"
WIN_PREFIX="$PREFIX"
WIN_LIBRARY_PREFIX="$LIBRARY_PREFIX"
WIN_BUILD_PREFIX="$BUILD_PREFIX"

# --- Path conversion ---------------------------------------------------------
# cygpath -u: Unix format (/cygdrive/c/...)  -- for shell operations
# cygpath -m: Mixed format (C:/...)          -- for compiler/configure args
# Avoid cygpath -ms (short 8.3 names) as PETSc compares PETSC_DIR against
# os.getcwd() which returns long paths.

export SRC_DIR=$(cygpath -u "$SRC_DIR")
export PREFIX=$(cygpath -u "$PREFIX")
export LIBRARY_PREFIX=$(cygpath -u "$LIBRARY_PREFIX")
export BUILD_PREFIX=$(cygpath -u "$BUILD_PREFIX")
export RECIPE_DIR=$(cygpath -u "$RECIPE_DIR")

MIX_LIBRARY_PREFIX=$(cygpath -m "$WIN_LIBRARY_PREFIX")
MIX_BUILD_PREFIX=$(cygpath -m "$WIN_BUILD_PREFIX")

# --- PATH setup --------------------------------------------------------------
# Prepend win32fe wrappers so PETSc configure finds them when given --with-cc=cl
export PATH="$SRC_DIR/lib/petsc/bin/win32fe:/usr/bin:$PATH"

# --- LIB / INCLUDE -----------------------------------------------------------
# These are inherited from cmd.exe in Windows format (semicolon-separated).
# MSVC cl.exe and ifort read them natively. Expand any literal %PREFIX%
# references that conda activation may have left unexpanded.

if [ -n "$LIB" ]; then
    LIB="${LIB//'%PREFIX%'/$WIN_PREFIX}"
    LIB="${LIB//'%LIBRARY_PREFIX%'/$WIN_LIBRARY_PREFIX}"
    LIB="${LIB//'%BUILD_PREFIX%'/$WIN_BUILD_PREFIX}"
    export LIB
fi
if [ -n "$INCLUDE" ]; then
    INCLUDE="${INCLUDE//'%PREFIX%'/$WIN_PREFIX}"
    INCLUDE="${INCLUDE//'%LIBRARY_PREFIX%'/$WIN_LIBRARY_PREFIX}"
    INCLUDE="${INCLUDE//'%BUILD_PREFIX%'/$WIN_BUILD_PREFIX}"
    export INCLUDE
fi

# --- Intel Fortran runtime libraries -----------------------------------------
# ifort needs its runtime libs (ifconsol.lib, libifcoremd.lib, etc.) on the
# LIB path for linking. Search common installation locations.

IFORT_LIB_DIR=""
for search_root in \
    "C:\\Program Files (x86)\\Intel\\oneAPI" \
    "C:\\Program Files\\Intel\\oneAPI" \
    "$WIN_BUILD_PREFIX"; do
    found=$(find "$(cygpath -u "$search_root")" -name "ifconsol.lib" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        IFORT_LIB_DIR=$(cygpath -w "$(dirname "$found")")
        break
    fi
done

if [ -n "$IFORT_LIB_DIR" ]; then
    echo "Found Intel Fortran runtime libraries at: $IFORT_LIB_DIR"
    export LIB="${LIB};${IFORT_LIB_DIR}"
else
    echo "ERROR: ifconsol.lib not found -- Fortran linking will fail"
    exit 1
fi

# --- Hide Cygwin link.exe ----------------------------------------------------
# Cygwin's /usr/bin/link.exe is a Unix hard-link utility. MSVC's link.exe is
# the Windows linker. PETSc's win32fe must find MSVC's version.

for f in /usr/bin/link /usr/bin/link.exe; do
    if [ -f "$f" ]; then
        mv "$f" "${f}.cygwin_hidden"
    fi
done

# --- Configure ----------------------------------------------------------------
export PETSC_DIR=$SRC_DIR
export PETSC_ARCH=arch-conda-c-opt

if [[ "${scalar}" == "complex" ]]; then
    with_hypre=0
else
    with_hypre=1
fi

# PETSc auto-expands --with-cc=cl to win32fe_cl.
# Mixed-format paths (C:/...) are used for --prefix and --with-*-dir args
# because win32fe can handle them and they produce cleaner installed paths.
/usr/bin/python3 ./configure \
    --with-cc=cl \
    --with-cxx=cl \
    --with-fc=ifort \
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
    --with-mpi-dir="${MIX_LIBRARY_PREFIX}" \
    --with-openmp=1 \
    --with-blaslapack-dir="${MIX_LIBRARY_PREFIX}" \
    --with-mkl_pardiso=1 \
    --with-hypre=${with_hypre} \
    --with-hypre-dir="${MIX_LIBRARY_PREFIX}" \
    --with-yaml=0 \
    --with-hwloc=0 \
    --with-metis=0 \
    --with-ptscotch=0 \
    --with-suitesparse=0 \
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
    --prefix="${MIX_LIBRARY_PREFIX}" \
    || (cat configure.log && exit 1)

# --- Build --------------------------------------------------------------------
/usr/bin/make MAKE_NP=${CPU_COUNT}
/usr/bin/make install

# --- Post-processing ---------------------------------------------------------

rm -f ${LIBRARY_PREFIX}/lib/petsc/conf/configure-hash
find ${LIBRARY_PREFIX}/lib/petsc -name '*.pyc' -delete

# Strip non-deterministic content (timestamps, machine info)
if [ -f "${LIBRARY_PREFIX}/include/petscmachineinfo.h" ]; then
    echo 'static const char *petscmachineinfo = "";' > "${LIBRARY_PREFIX}/include/petscmachineinfo.h"
fi
if [ -f "${LIBRARY_PREFIX}/include/petscconfiginfo.h" ]; then
    echo 'static const char *petscconfigureruntime = "";' > "${LIBRARY_PREFIX}/include/petscconfiginfo.h"
fi

rm -f ${LIBRARY_PREFIX}/lib/petsc/conf/reconfigure-*.py

# Fix build-prefix references in installed files.
# PETSc under Cygwin may write paths in Cygwin (/cygdrive/c/...),
# mixed (C:/...), or Windows (C:\...) format. Handle all variants.
WIN_BUILD_PREFIX_FWD=$(echo "$WIN_BUILD_PREFIX" | tr '\\' '/')
for f in $(grep -rle "${BUILD_PREFIX}\|${MIX_BUILD_PREFIX}\|${WIN_BUILD_PREFIX_FWD}" \
           "${LIBRARY_PREFIX}/lib/petsc" 2>/dev/null) \
         "${LIBRARY_PREFIX}/lib/pkgconfig/PETSc.pc"; do
    [ -f "$f" ] || continue
    echo "Fixing build prefix references in $f"
    sed -i'' \
        -e "s|${BUILD_PREFIX}/Library/bin/||g" \
        -e "s|${MIX_BUILD_PREFIX}/Library/bin/||g" \
        -e "s|${BUILD_PREFIX}|${LIBRARY_PREFIX}|g" \
        -e "s|${MIX_BUILD_PREFIX}|${MIX_LIBRARY_PREFIX}|g" \
        -e "s|${WIN_BUILD_PREFIX_FWD}|${MIX_LIBRARY_PREFIX}|g" \
        "$f"
done

for f in $(grep -rle "${BUILD_PREFIX}\|${MIX_BUILD_PREFIX}\|${WIN_BUILD_PREFIX_FWD}" \
           "${LIBRARY_PREFIX}/include" 2>/dev/null); do
    echo "Fixing build prefix in header $f"
    sed -i'' \
        -e "s|${BUILD_PREFIX}|${LIBRARY_PREFIX}|g" \
        -e "s|${MIX_BUILD_PREFIX}|${MIX_LIBRARY_PREFIX}|g" \
        -e "s|${WIN_BUILD_PREFIX_FWD}|${MIX_LIBRARY_PREFIX}|g" \
        "$f"
done

rm -rf ${LIBRARY_PREFIX}/share/petsc/examples/src
rm -rf ${LIBRARY_PREFIX}/share/petsc/datafiles

# --- Cleanup ------------------------------------------------------------------
# Restore Cygwin's link.exe (build env is ephemeral, but good practice)
for f in /usr/bin/link.cygwin_hidden /usr/bin/link.exe.cygwin_hidden; do
    if [ -f "$f" ]; then
        mv "$f" "${f%.cygwin_hidden}"
    fi
done
