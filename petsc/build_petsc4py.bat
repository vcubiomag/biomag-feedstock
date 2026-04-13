@echo on

@SET "PETSC_DIR=%LIBRARY_PREFIX%"

@REM PETSc headers require MSVC's conformant preprocessor for advanced
@REM token-pasting macros (PetscDefined, PETSC_DEPRECATED_FUNCTION, etc.).
@REM petsc4py's setup.py skips compiler config for non-unix compilers,
@REM so PETSc's CC_FLAGS (which include /Zc:preprocessor) are never applied.
@SET "CL=/Zc:preprocessor"

@REM petsc4py directly calls MPI functions (MPI_Barrier, MPI_Comm_rank, etc.)
@REM but confpetsc.py only links external libs for static PETSc builds.
@REM With shared PETSc, we must explicitly link msmpi.lib via the LINK env var.
@SET "LINK=msmpi.lib"

cd src/binding/petsc4py
%PYTHON% conf/cythonize.py
%PYTHON% -m pip install . -vv --no-deps --no-build-isolation
