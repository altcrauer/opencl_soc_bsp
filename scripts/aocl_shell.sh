export MY_QUARTUS_INSTALL_DIR=/altera/14.0

export ALTERAOCLSDKROOT=$MY_QUARTUS_INSTALL_DIR/hld
#export QUARTUS_ROOTDIR=$MY_QUARTUS_INSTALL_DIR/quartus
#export PATH=$PATH:$QUARTUS_ROOTDIR/bin
export PATH=$PATH:$ALTERAOCLSDKROOT/bin
#export LD_LIBRARY_PATH=$ALTERAOCLSDKROOT/linux64/lib

#board stuff
#export BOARD_ROOT=/altera/altera_nas/beta_stuff/opencl_soc_130/install/c5soc
export BOARD_ROOT=$ALTERAOCLSDKROOT/board/c5soc
export AOCL_BOARD_PACKAGE_ROOT=$BOARD_ROOT
export AOCL_COMPILER=arm-linux-gnueabihf-g++
bash