#init_opencl_script

#get exact script path
SCRIPT_PATH=`readlink -f ${BASH_SOURCE[0]}`
#get director of script path
SCRIPT_DIR_PATH="$(dirname $SCRIPT_PATH)"

export ALTERAOCLSDKROOT=$SCRIPT_DIR_PATH/opencl_arm32_rte
export AOCL_BOARD_PACKAGE_ROOT=$ALTERAOCLSDKROOT/board/c5soc
export PATH=$ALTERAOCLSDKROOT/bin:$PATH
export LD_LIBRARY_PATH=$ALTERAOCLSDKROOT/host/arm32/lib:$LD_LIBRARY_PATH

function check_fpga_user_mode() {
	local FPGA_STATUS=`cat /sys/class/fpga/fpga0/status`
	if [ "$FPGA_STATUS" == "user mode" ]; then
		echo "1"
	else
		echo "0"
	fi
}

function load_opencl_rbf() {
		local OPENCL_RBF_FILE="opencl.rbf"
	
		#first try to load the rbf if available
		if [ -e $OPENCL_RBF_FILE ]; then
			#shutdown bridges
			echo 0 > /sys/class/fpga-bridge/fpga2hps/enable
			echo 0 > /sys/class/fpga-bridge/hps2fpga/enable
			echo 0 > /sys/class/fpga-bridge/lwhps2fpga/enable
			
			cat $SCRIPT_DIR_PATH/$OPENCL_RBF_FILE > /dev/fpga0
			
			if [ $(check_fpga_user_mode) == "0" ]; then
				echo "FPGA programming failed!  Cannot proceed!"
				exit 1
			fi
			
			#enable bridges
			echo 1 > /sys/class/fpga-bridge/fpga2hps/enable
			echo 1 > /sys/class/fpga-bridge/hps2fpga/enable
			echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable
			
			echo "$OPENCL_RBF_FILE programmed to FPGA"
		fi
}

if [ -e "/dev/acl0" ]; then
	echo "driver is already loaded"
else
	if [ $(check_fpga_user_mode) == "1" ]; then
		
		#program the FPGA with the initial opencl rbf.  This is only necessary
		#if there is a non-opencl FPGA image currently loaded.  Normally,
		#one of these images is loaded by default at boot time.
		load_opencl_rbf
		
		insmod $AOCL_BOARD_PACKAGE_ROOT/driver/aclsoc_drv.ko
		
		if [ ! -e "/dev/acl0" ]; then
			echo "driver load failed unexpectedly"
		fi
	
		echo "OpenCL Driver loaded"
	else
		echo "FPGA is not programmed.  You can't load the driver without an" 
		echp "FPGA image already progammed into the FPGA"
		echo ""
		echo "Are your MSEL jumper settings correct?"
	fi
fi

