shell make all `0'
cap noi ado uninstall honestdid
mata: mata clear
mata: mata set matastrict on
mata: mata set mataoptimize on
cap noi mkdir src
cap noi mkdir src/build
cap noi erase src/build/lhonestdid.mlib
do src/mata/osqp.mata
do src/mata/ecos.mata
do src/mata/flci.mata
do src/mata/honestdid.mata
mata: mata mlib create lhonestdid, dir("src/build") replace
mata: mata mlib add lhonestdid Honest*() _honest*() _flci*() OSQP*() ECOS*(), dir("src/build") complete
net install honestdid, from(`c(pwd)') replace