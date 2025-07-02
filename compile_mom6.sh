#!/bin/bash
module purge
cluster=`hostname` #three options: tigercpu, stellar-amd, and tiger3
BASEDIR=$(pwd);
if [ "$cluster" = "tigercpu.princeton.edu" ]; then
   echo "Compiling on tigercpu"
   module load intel-mpi/intel/2018.3/64 intel/18.0/64/18.0.3.222 hdf5/intel-16.0/intel-mpi/1.8.16 netcdf/intel-16.0/hdf5-1.8.16/intel-mpi/4.4.0
   MKF_TEMPLATE="$BASEDIR/tigercpu-intel_optimized.mk"
elif [ "$cluster" = "stellar-amd.princeton.edu" ]; then
   echo "Compiling on stellar-amd"
   module load intel/2021.1.2 intel-mpi/intel/2021.3.1 hdf5/intel-2021.1/intel-mpi/1.10.6 netcdf/intel-2021.1/hdf5-1.10.6/intel-mpi/4.7.4
   MKF_TEMPLATE="$BASEDIR/stellar-amd.mk"
elif [ "$cluster" = "tiger3.princeton.edu" ]; then
   mpi_imp="openmpi" #two options: openmpi and intelmpi
   echo "Compiling on tiger3"
   sed -i 's/static pid_t gettid(void)/extern pid_t gettid(void)/' src/FMS/affinity/affinity.c   #this avoids a "static declaration of gettid" error
   #these lines change the default resources requested for proper load balancing
   sed -i 's/--nodes .*/--nodes 6                             # number of nodes requested/' */*/slurmjob.sh
   sed -i 's/--ntasks-per-node.*/--ntasks-per-node=112                  # how many tasks per node/' */*/slurmjob.sh
   sed -i 's/--ntasks-per-socket.*/--ntasks-per-socket=56                 # how many tasks per socket, two sockets per node/' */*/slurmjob.sh
   if [ "$mpi_imp" = "openmpi" ]; then
      echo "Using openmpi"
      module load intel-tbb/2021.13 intel-rt/2024.2 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 netcdf/oneapi-2024.2/hdf5-1.14.4/openmpi-4.1.6/4.9.2
      MKF_TEMPLATE="$BASEDIR/tiger3-intel_openmpi.mk"
      export OMPI_F90=ifort
      export OMPI_FC=ifort
   elif [ "$mpi_imp" = "intelmpi" ]; then
      echo "Using intelmpi"
      module load intel-tbb/2021.13 intel-rt/2024.2 intel-oneapi/2024.2 intel-mpi/oneapi/2021.13 hdf5/oneapi-2024.2/intel-mpi/1.14.4 netcdf/oneapi-2024.2/hdf5-1.14.4/intel-mpi/4.9.2
      MKF_TEMPLATE="$BASEDIR/tiger3-intel_optimized.mk"
   else
      echo "Please choose an mpi implementation for running on tiger3 (openmpi or intelmpi)"
   fi
else
   echo "Please use a Princeton cluster with this compilation script (tigercpu, stellar-amd, or tiger3)"
   exit 1
fi

#link datasets to current MOM6
if [ ! -e .datasets ]
then
    ln -s /scratch/gpfs/GEOCLIM/LRGROUP/datasets .datasets
fi

# compile label for bio or ocean-ice
# be careful with the compile label (clab) here, there are only three options: ocean_ice_bgc, ocean_ice, ocean_only 
clab='ocean_only'; #only three options: ocean_ice_bgc, ocean_ice, ocean_only

regional_bgc='false'; # true or false to open regional cobalt, the exe_name will be clab_regional

tide='false'; # true or false to open tide, the exe_name will be clab_tide

kw_dm18='false'; # true or false to turn on kw_dm18 which should only work for global bgc
                # kw_dm18 uses Luc's method to compute dic_kw

kw_d25='false'; # true or false to turn on kw_d25 which should only work for global bgc

#can rename the exename
EXENAME=$clab #"_tide" #"mom6_lrgroup_bio"

#set the default branch in the begining compile
#cd src/MOM6;       git checkout lrgroup/default
#cd ../SIS2;        git checkout lrgroup/default
#cd ../ocean_BGC;   git checkout lrgroup/default
#cd ../FMS1;        git checkout origin/release/2019.01 # GFDL MOM6-examples default version and change one line to speed up BGC 
#cd ../coupler;     git checkout lrgroup/default; git checkout 14578f0 #GFDL MOM6-examples default version (14578f0)
#cd ../atmos_null;  git checkout lrgroup/default; git checkout aeac506 #GFDL MOM6-examples default version (aeac506)
#cd ../../

if $regional_bgc; then 
   # get FMS version with Andrew's fast OBC speed
   echo "switching src/FMS to origin/release/2021.03 branch..." #2021 03 version is an suggested version by Andrew
   cd src/FMS1;  git checkout lrgroup/default; git checkout 8883101 #This is the version right after origin/release/2021.03 

   echo "switching src/ocean_BGC to lrgroup/regional_default branch with regionally tuned parameters..."
   cd ../ocean_BGC;  git checkout lrgroup/regional_default 

   # go back to main directory
   cd ../../
   EXENAME=$EXENAME"_regional" #add regional to exe_name
fi

if $tide; then #[[ "$clab" = *"tide"* ]]; then
   echo "switching src/coupler to revised version including gregorian calendar..."
   cd src/coupler; git checkout lrgroup/tide_gregorian_14578f0
   cd ../../
   EXENAME=$EXENAME"_tide" #add tide to exe_name
fi

if $kw_dm18 && [[ "$clab" = *"ocean_ice_bgc"* ]]; then 
   echo "switching src/atmos_null to kw_dm18 version including hs computation..."
   cd src/atmos_null; git checkout lrgroup/kw_dm18

   echo "switching src/coupler to kw_dm18 version including hs computation..."
   cd ../coupler;     git checkout lrgroup/kw_dm18

   echo "switching src/FMS1 to kw_dm18 version including hs computation..."
   cd ../FMS1;        git checkout lrgroup/kw_dm18
   EXENAME=$EXENAME"_kw_dm18" #add kw_name to exe_name
   cd ../../
   if $tide || $regional_bgc; then
      echo "kw_dm18 only test for global ocean, not for regional bgc or tide"
      exit
   fi
fi

if $kw_d25 && [[ "$clab" = *"ocean_ice_bgc"* ]]; then 
   echo "switching src/atmos_null to kw_d25 version including hs computation..."
   cd src/atmos_null; git checkout lrgroup/kw_d25

   echo "switching src/coupler to kw_d25 version including hs computation..."
   cd ../coupler;     git checkout lrgroup/kw_d25

   echo "switching src/ocean_bgc to kw_d25 version including hs computation..."
   cd ../FMS1;        git checkout -f lrgroup/kw_d25

   echo "switching src/FMS1 to kw_d25 version including hs computation..."
   cd ../ocean_BGC;        git checkout lrgroup/kw_d25

   EXENAME=$EXENAME"_kw_dm25" #add kw_name to exe_name
   cd ../../
   if $tide || $regional_bgc; then
      echo "kw_d25 only test for global ocean, not for regional bgc or tide"
      exit
   fi
fi

 
echo "Compile FMS"
mkdir -p build/intel/shared/repro/
(cd build/intel/shared/repro/; rm -f path_names; \
"$BASEDIR/src/mkmf/bin/list_paths" -l "$BASEDIR/src/FMS"; \
"$BASEDIR/src/mkmf/bin/mkmf" -t $MKF_TEMPLATE -p libfms.a -c "-Duse_libMPI -Duse_netCDF -DSPMD -DMAXFIELDMETHODS_=400" path_names)

echo "Make NETCDF "
#By default we were forcing compilation with the REPRO configuration. The configuration can now be changed by going into the tiger3-intel_optimized.mk (line 18) Makefile and setting either:
# OPT = 1    -- compiles with the optimized configuration for fastest runtimes, but may be unstable (uses O3 and avx512)
# REPRO = 1  -- compiles with the reproduction configuration (uses O2 and avx2) for reproducability and stability
# DEBUG = 1  -- turns off all optimizations and sets useful checks, memory sanitation is disabled for now

#(cd build/intel/shared/repro/; source ../../env; make clean; make NETCDF=3 REPRO=1 libfms.a -j)
(cd build/intel/shared/repro/; source ../../env; make clean; make NETCDF=3 libfms.a -j)

echo "List Model Code paths"
BUILDDIR="build/intel/$EXENAME/repro/"
mkdir -p $BUILDDIR

if [[ "$clab" = "ocean_only" ]]; then
   (cd $BUILDDIR; rm -f path_names; \
   "$BASEDIR/src/mkmf/bin/list_paths" -v -v -v ./ $BASEDIR/src/MOM6/config_src/{infra/FMS1,memory/dynamic_symmetric,drivers/solo_driver,external} $BASEDIR/src/MOM6/pkg/GSW-Fortran/{modules,scripts,toolbox} $BASEDIR/src/MOM6/src/{*,*/*}/)

   echo "Compile Model ocean_only and make executable file"
   (cd $BUILDDIR; \
   "$BASEDIR/src/mkmf/bin/mkmf" -t $MKF_TEMPLATE -o '-I../../shared/repro' -p $EXENAME -l '-L../../shared/repro -lfms' -c '-Duse_libMPI -Duse_netCDF -DSPMD -D_USE_MOM6_DIAG -DUSE_PRECISION=2' path_names )

elif [[ "$clab" = "ocean_ice" ]]; then
   # this is the default compile for ocean-ice model which is non-bio and non-symmetrical
   (cd $BUILDDIR; rm -f path_names; \
   "$BASEDIR/src/mkmf/bin/list_paths" -v -v -v ./ $BASEDIR/src/MOM6/config_src/{infra/FMS1,memory/dynamic_symmetric,drivers/FMS_cap,external} $BASEDIR/src/MOM6/pkg/GSW-Fortran/{modules,scripts,toolbox} $BASEDIR/src/MOM6/src/{*,*/*}/ $BASEDIR/src/{atmos_null,coupler,land_null,ice_param,icebergs,SIS2,FMS/coupler,FMS/include}/) 

   echo "Compile Model ocean_ice and make executable file"
   (cd $BUILDDIR; \
   "$BASEDIR/src/mkmf/bin/mkmf" -t $MKF_TEMPLATE -o '-I../../shared/repro' -p $EXENAME -l '-L../../shared/repro -lfms' -c '-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_ -D_USE_MOM6_DIAG -DUSE_PRECISION=2' path_names )

elif [[ "$clab" = *"ocean_ice_bgc"* ]]; then
   # compile MOM6-SIS2-COBALT bgc module
   #is there a reason why we are listing all the src/external paths separately here??
   (cd $BUILDDIR; rm -f path_names; \
   "$BASEDIR/src/mkmf/bin/list_paths" -v -v -v ./ $BASEDIR/src/MOM6/config_src/{infra/FMS1,memory/dynamic_symmetric,drivers/FMS_cap,external/ODA_hooks,external/drifters,external/stochastic_physics,external/database_comms,external/MARBL} $BASEDIR/src/MOM6/pkg/GSW-Fortran/{modules,scripts,toolbox} $BASEDIR/src/MOM6/src/{*,*/*}/ $BASEDIR/src/{atmos_null,coupler,land_null,ice_param,icebergs,SIS2,FMS/coupler,FMS/include}/ $BASEDIR/src/ocean_BGC/{generic_tracers,mocsy/src})

   echo "Compile Model ocean_ice_bgc and make executable file"
   (cd $BUILDDIR; \
   "$BASEDIR/src/mkmf/bin/mkmf" -t $MKF_TEMPLATE -o '-I../../shared/repro' -p $EXENAME -l '-L../../shared/repro -lfms' -c '-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_ -D_USE_MOM6_DIAG -D_USE_GENERIC_TRACER -DUSE_PRECISION=2' path_names )
fi

(cd $BUILDDIR; source ../../env;make clean; make NETCDF=3 $EXENAME -j)





