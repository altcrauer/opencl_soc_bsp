#get exact script path
SCRIPT_PATH=`readlink -f ${BASH_SOURCE[0]}`
#get director of script path
SCRIPT_DIR_PATH="$(dirname $SCRIPT_PATH)"

#init_opencl_script
function check_fpga_user_mode() {
	local FPGA_STATUS=`cat /sys/class/fpga/fpga0/status`
	if [ "$FPGA_STATUS" == "user mode" ]; then
		echo "1"
	else
		echo "0"
	fi
}

function load_ghrd_rbf() {
		local OPENCL_RBF_FILE="ghrd.rbf"
	
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
	rmmod aclsoc_drv
	echo "OpenCL Driver unloaded sucessfully"
	load_ghrd_rbf
else
	echo "OpenCL Driver has not been loaded"
fi
