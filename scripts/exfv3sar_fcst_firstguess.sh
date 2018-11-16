#!/bin/sh -l

################################################################################
####  UNIX Script Documentation Block
#                      .                                             .
# Script name:         exfv3sar_fcst_firstguess.sh
# Script description:  Run 6-h FV3SAR Forecast from t-12h to t-6h. The 6-h forecast
#                      is used as the first guess to start the Fv3SAR hourly DA cycle    
#
# Script history log:
# 2018-10-30  Eric Rogers - Modified based on original chgres job
# 2018-11-09  Ben Blake   - Moved various settings into J-job script
#
################################################################################

set -x

ulimit -s unlimited
ulimit -a

export KMP_AFFINITY=scatter
export OMP_NUM_THREADS=2
export OMP_STACKSIZE=1024m

mkdir -p INPUT RESTART
cp ${NWGES}/gfsanl.tm12/*.nc INPUT

numbndy=`ls -1 INPUT/gfs_bndy.tile7*.nc | wc -l`

#needed for err_exit
export SENDECF=NO

if [ $numbndy -ne 3 ] ; then
  export err=3
  echo "Don't have all 3 BC files, abort run"
  err_exit "Don't have all 3 BC files, abort run"
fi

cp $FIX_AM/global_solarconstant_noaa_an.txt  solarconstant_noaa_an.txt
cp $FIX_AM/ozprdlos_2015_new_sbuvO3_tclm15_nuchem.f77  INPUT/global_o3prdlos.f77
cp $FIX_AM/global_h2o_pltc.f77                         INPUT/global_h2oprdlos.f77
cp $FIX_AM/ozprdlos_2015_new_sbuvO3_tclm15_nuchem.f77  global_o3prdlos.f77
cp $FIX_AM/global_h2o_pltc.f77                         global_h2oprdlos.f77
cp $FIX_AM/global_sfc_emissivity_idx.txt 	sfc_emissivity_idx.txt
cp $FIX_AM/global_co2historicaldata_glob.txt co2historicaldata_glob.txt
cp $FIX_AM/co2monthlycyc.txt             	co2monthlycyc.txt
cp $FIX_AM/global_climaeropac_global.txt 	aerosol.dat

cp $FIX_AM/global_glacier.2x2.grb .
cp $FIX_AM/global_maxice.2x2.grb .
cp $FIX_AM/RTGSST.1982.2012.monthly.clim.grb .
cp $FIX_AM/global_snoclim.1.875.grb .
cp $FIX_AM/global_snowfree_albedo.bosu.t126.384.190.rg.grb .
cp $FIX_AM/global_albedo4.1x1.grb .
cp $FIX_AM/CFSR.SEAICE.1982.2012.monthly.clim.grb .
cp $FIX_AM/global_tg3clim.2.6x1.5.grb .
cp $FIX_AM/global_vegfrac.0.144.decpercent.grb .
cp $FIX_AM/global_vegtype.igbp.t126.384.190.rg.grb .
cp $FIX_AM/global_soiltype.statsgo.t126.384.190.rg.grb .
cp $FIX_AM/global_soilmgldas.t126.384.190.grb .
cp $FIX_AM/seaice_newland.grb .
cp $FIX_AM/global_shdmin.0.144x0.144.grb .
cp $FIX_AM/global_shdmax.0.144x0.144.grb .
cp $FIX_AM/global_slope.1x1.grb .
cp $FIX_AM/global_mxsnoalb.uariz.t126.384.190.rg.grb .
#
for file in `ls $CO2DIR/global_co2historicaldata* ` ; do
  cp $file $(echo $(basename $file) |sed -e "s/global_//g")
done
#
#copy tile data and orography for regional
#
res=768
ntiles=7
tile=7
while [ $tile -le $ntiles ]; do
  cp $FIXDIR/C${res}/C${res}_grid.tile${tile}.halo3.nc INPUT/.
  cp $FIXDIR/C${res}/C${res}_grid.tile${tile}.halo4.nc INPUT/.
  cp $FIXDIR/C${res}/C${res}_oro_data.tile${tile}.halo0.nc INPUT/.
  cp $FIXDIR/C${res}/C${res}_oro_data.tile${tile}.halo4.nc INPUT/.
  tile=`expr $tile + 1 `
done
cp $FIXDIR/C${res}/C${res}_mosaic.nc INPUT/.

cd INPUT
ln -sf C768_mosaic.nc grid_spec.nc
ln -sf C${res}_grid.tile7.halo3.nc C${res}_grid.tile7.nc
ln -sf C${res}_grid.tile7.halo4.nc grid.tile7.halo4.nc
ln -sf C${res}_oro_data.tile7.halo0.nc oro_data.nc
ln -sf C${res}_oro_data.tile7.halo4.nc oro_data.tile7.halo4.nc
ln -sf sfc_data.tile7.nc sfc_data.nc
ln -sf gfs_data.tile7.nc gfs_data.nc
cd ..

# Copy or set up files data_table, diag_table, field_table,
# input.nml, input_nest02.nml, model_configure, and nems.configure
#
cp ${CONFIGdir}/diag_table_firstguess.tmp diag_table_mp.tmp
cp ${CONFIGdir}/data_table .
cp ${CONFIGdir}/field_table .
cp ${CONFIGdir}/input.nml_firstguess input.nml
cp ${CONFIGdir}/model_configure_firstguess.tmp .
cp ${CONFIGdir}/nems.configure .

NODES=40
ncnode=12    #-- 12 tasks per node on Cray

let nctsk=ncnode/OMP_NUM_THREADS
##let ntasks=NODES*nctsk
let ntasks=NODES*ncnode
echo nctsk = $nctsk and ntasks = $ntasks

yr=`echo $CYCLEtm12 | cut -c1-4`
mn=`echo $CYCLEtm12 | cut -c5-6`
dy=`echo $CYCLEtm12 | cut -c7-8`
hr=`echo $CYCLEtm12 | cut -c9-10`

cat > temp << !
${yr}${mn}${dy}.${hr}Z.${RES}.32bit.non-hydro
$yr $mn $dy $hr 0 0
!

cat temp diag_table_mp.tmp > diag_table

cat model_configure_firstguess.tmp | sed s/NTASKS/$ntasks/ | sed s/YR/$yr/ | \
    sed s/MN/$mn/ | sed s/DY/$dy/ | sed s/H_R/$hr/ | \
    sed s/NHRS/$NHRSguess/ | sed s/NTHRD/$OMP_NUM_THREADS/ | \
    sed s/NCNODE/$ncnode/  >  model_configure


export pgm=global_fv3gfs.x
. prep_step

startmsg
mpirun -l -n ${ntasks} $EXECfv3/global_fv3gfs.x >$pgmout 2>err
export err=$?;err_chk

# Copy files needed for tm06 analysis
# use grid_spec.nc file output from model in working directory, 
# NOT the one in the INPUT directory.......

cp grid_spec.nc $GUESSdir/.
cd RESTART
mv ${PDYtm06}.${CYCtm06}0000.coupler.res $GUESSdir/.
mv ${PDYtm06}.${CYCtm06}0000.fv_core.res.nc $GUESSdir/.
mv ${PDYtm06}.${CYCtm06}0000.fv_core.res.tile1.nc $GUESSdir/.
mv ${PDYtm06}.${CYCtm06}0000.fv_tracer.res.tile1.nc $GUESSdir/.
mv ${PDYtm06}.${CYCtm06}0000.sfc_data.nc $GUESSdir/.

# These are not used in GSI but are needed to warmstart FV3
# so they go directly into ANLdir
mv ${PDYtm06}.${CYCtm06}0000.phy_data.nc $ANLdir/phy_data.nc
mv ${PDYtm06}.${CYCtm06}0000.fv_srf_wnd.res.tile1.nc $ANLdir/fv_srf_wnd.res.tile1.nc
cd ../

exit
