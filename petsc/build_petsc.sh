#!/bin/bash
set -ex

# Get updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* .

export PETSC_DIR=$SRC_DIR
export PETSC_ARCH=arch-conda-c-opt

if [[ "$mpi" == "openmpi" ]]; then
  export OMPI_CC=$CC
  export OPAL_PREFIX=$PREFIX
fi

if [[ "$CONDA_BUILD_CROSS_COMPILATION" == "1" ]]; then
  extra_opts="--with-batch"
fi

# Unexport compiler variables to reduce warnings about config we know isn't used
# (PETSc configure manages its own compiler detection)
export -n AR FC F90 F77 CC CXX CPP RANLIB
export -n CFLAGS CXXFLAGS CPPFLAGS FFLAGS LDFLAGS

# Hypre is only available for real scalar type (no complex builds on conda-forge)
if [[ "${scalar}" == "complex" ]]; then
  with_hypre="0"
else
  with_hypre="1"
fi

python ./configure \
  AR="${AR:-ar}" \
  CPP="$CPP" \
  RANLIB="$RANLIB" \
  CC="mpicc" \
  CXX="mpicxx" \
  FC="mpifort" \
  CPPFLAGS="$CPPFLAGS" \
  LDFLAGS="$LDFLAGS" \
  --COPTFLAGS="$CFLAGS -O3" \
  --CXXOPTFLAGS="$CXXFLAGS -O3" \
  --FOPTFLAGS="$FFLAGS -O3" \
  --with-clib-autodetect=0 \
  --with-cxxlib-autodetect=0 \
  --with-fortranlib-autodetect=0 \
  --with-debugging=0 \
  --with-shared-libraries \
  --with-ssl=0 \
  --with-x=0 \
  --with-scalar-type=${scalar} \
  --with-mpi=1 \
  --with-openmp=1 \
  --with-pthread=1 \
  --with-blaslapack-dir=$PREFIX \
  --with-mkl_pardiso=1 \
  --with-yaml=1 \
  --with-hdf5=1 \
  --with-fftw-include=$PREFIX/include \
  --with-fftw-lib=[-L$PREFIX/lib,-lfftw3_mpi,-lfftw3] \
  --with-hwloc=1 \
  --with-hypre=${with_hypre} \
  --with-metis=1 \
  --with-parmetis=1 \
  --with-ptscotch=1 \
  --with-scalapack=1 \
  --with-mumps=1 \
  --with-superlu=1 \
  --with-superlu_dist=1 \
  --with-superlu_dist-include=$PREFIX/include/superlu-dist \
  --with-superlu_dist-lib=-lsuperlu_dist \
  --with-suitesparse=1 \
  --with-suitesparse-dir=$PREFIX \
  --with-cuda=0 \
  $extra_opts \
  --prefix=$PREFIX || (cat configure.log && exit 1)

# Verify that gcc_ext isn't linked
for f in $PETSC_ARCH/lib/petsc/conf/petscvariables $PETSC_ARCH/lib/pkgconfig/PETSc.pc; do
  if grep gcc_ext "$f"; then
    echo "gcc_ext found in $f"
    exit 1
  fi
done

sedinplace() {
  if [[ $(uname) == Darwin ]]; then
    sed -i "" "$@"
  else
    sed -i"" "$@"
  fi
}

# Remove absolute path to build python
sedinplace "s%${BUILD_PREFIX}/bin/python%python%g" $PETSC_ARCH/include/petscconf.h
sedinplace "s%${BUILD_PREFIX}/bin/python%python%g" $PETSC_ARCH/lib/petsc/conf/petscvariables
sedinplace "s%${BUILD_PREFIX}/bin/python%/usr/bin/env python%g" $PETSC_ARCH/lib/petsc/conf/reconfigure-arch-conda-c-opt.py

# Replace absolute paths with $PREFIX
for path in $PETSC_DIR $BUILD_PREFIX; do
    for f in $(grep -l "${path}" $PETSC_ARCH/include/petsc*.h); do
        echo "Fixing ${path} in $f"
        sedinplace s%${path}%\${PREFIX}%g $f
    done
done

make MAKE_NP=${CPU_COUNT}
make install

# Cleanup
rm -f ${PREFIX}/lib/petsc/conf/configure-hash
find $PREFIX/lib/petsc -name '*.pyc' -delete

# Strip non-deterministic content (timestamps, machine info) from installed files
# to ensure reproducible package hashes across builds.
# These files contain multiline string literals with build dates, hostnames, and
# system info that change every build. Overwrite with empty stubs.
if [ -f "${PREFIX}/include/petscmachineinfo.h" ]; then
  echo "Stripping petscmachineinfo.h"
  echo 'static const char *petscmachineinfo = "";' > "${PREFIX}/include/petscmachineinfo.h"
fi
if [ -f "${PREFIX}/include/petscconfiginfo.h" ]; then
  echo "Stripping petscconfiginfo.h"
  echo 'static const char *petscconfigureruntime = "";' > "${PREFIX}/include/petscconfiginfo.h"
fi

# Remove the reconfigure script (contains build-specific paths and timestamps)
rm -f ${PREFIX}/lib/petsc/conf/reconfigure-*.py

# Remove build prefix references from installed files
for f in $(grep -l "${BUILD_PREFIX}/bin/" -R "${PREFIX}/lib/petsc") "$PREFIX/lib/pkgconfig/PETSc.pc"; do
  echo "Fixing ${BUILD_PREFIX}/bin/ in $f"
  grep "${BUILD_PREFIX}/bin/" "$f" || true
  sedinplace s%${BUILD_PREFIX}/bin/%%g $f
done

for f in $(grep -l "${BUILD_PREFIX}" -R "${PREFIX}/lib/petsc") "$PREFIX/lib/pkgconfig/PETSc.pc"; do
  echo "Fixing ${BUILD_PREFIX} in $f"
  grep "${BUILD_PREFIX}" "$f" || true
  sedinplace s%${BUILD_PREFIX}%${PREFIX}%g $f
done

# Remove example and data files
echo "Removing example files"
rm -fr $PREFIX/share/petsc/examples/src
echo "Removing data files"
rm -fr $PREFIX/share/petsc/datafiles
