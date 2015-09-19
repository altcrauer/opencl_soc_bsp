export QSYS_BASE=system
export QSYS_HPS_INST_NAME=acl_iface_hps
export PRELOADER_DIR=software/preloader
mkdir -p $PRELOADER_DIR
cp *.patch $PRELOADER_DIR
bsp-create-settings \
	--type spl \
	--bsp-dir $PRELOADER_DIR \
	--preloader-settings-dir "hps_isw_handoff/${QSYS_BASE}_${QSYS_HPS_INST_NAME}" \
	--settings $PRELOADER_DIR/settings.bsp \
	--set spl.boot.WATCHDOG_ENABLE false
