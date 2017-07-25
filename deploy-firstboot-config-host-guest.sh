#!/bin/bash

LOG_PATH=/root/deploy-host-guest.log
NO_OVERWRITE_LOG_FLAG=1
REPORT=/root/report_file

. /root/global.functions

if [[ $? != 0 ]]; then
	echo "Can't find file '/root/global.functions'"; exit 1
fi

#### deploy-host.sh
########################################################################################

# Function for coping file from /root
############################################

function config_distribute_files()
{
	para_fun_l $*; start_function config_distribute_files "Backup yum repo configuration"

    run_com -Ee "cp -r /etc/yum.repos.d /etc/yum.repos.d.bak"

	end_function
}

# Function for copying rpm to repo
############################################

function config_copy_rpms_2_repo()
{
	para_fun_l $*; start_function config_copy_rpms_2_repo "Copy rpms to repo"
	
	define_var -Eec yum_dir "/var/www/html"
	define_var -Eec repo_dir "$yum_dir/peerapp_repo"
	
	if [[ -d $repo_dir ]]; then

		echo_log "**** Remove old directory yum repo"

		run_com -Ee "rm -rf $yum_dir/peerapp_repo"
	fi

	echo_log "**** Copy RPM's to yum repo\nPlease wait..."
		
	run_com -Ee "mkdir $repo_dir"
	run_com -Ee "cp /root/comps.xml $repo_dir" 
	run_com -Ee "cp /root/Packages/*rpm $repo_dir"
	run_com -Ee "cd $repo_dir"
	run_com -Ee "createrepo -v -g comps.xml ."

	# speedup yum
	define_var -Ee yum_plugin_file "/etc/yum/pluginconf.d/fastestmirror.conf"
	
	run_com -Ee "cp $yum_plugin_file $yum_plugin_file.bak"
	replace_str_4_file -Ee $yum_plugin_file "enabled=1" "enabled=0"

	end_function
}

# Function for copying iso
############################################

function copy_iso()
{
	para_fun_l $*; start_function copy_iso "Copy ISO image to host"

	run_com_if -Ee "! -d $VM_IMG_DIR" "mkdir $VM_IMG_DIR"
	update_env_file "ISO_FILE=$VM_IMG_DIR/ub.iso"

	if [[ -f $ISO_FILE ]]; then
		display -Wf "ISO file '$ISO_FILE' is already exists"; end_function; return 	
	fi

	run_com -Ee "echo > $temp"

	var -Ee sd_list "ls /sys/class/block/sd*/removable"
	
	for l in $sd_list; do
	    var -Ee sdname "echo $l | sed s_/sys/class/block/__ | sed s_/removable__"
	    var -Ee sddev "lsblk -dn | grep $sdname | wc -l"
	    run_com_if -Ee "$sddev -ne 0" "echo \"`echo $l | awk -F '/' '{print \"/dev/\"\$5}'` `cat $l`\" >> $temp"
    done
    
    var -Ee num_iso "grep -c 1 $temp"
	display_if_not  -Ee "$num_iso = 1" "More then one USB has been found"

	var -Ee USB "awk '/ 1/ {print \$1}' $temp"

	run_com -Ee "mount $USB /mnt"
	var -Ee SIZE "du -sm /mnt | awk '{print \$1;}'"
	run_com -Ee "umount /mnt"
	
	echo_log "Copying ISO. Please wait few minutes"
	
	run_com -Ee "dd if=$USB count=$SIZE oflag=sync bs=1M | pv |dd of=$ISO_FILE"
	
	define_var_if_else -Ee size_file "-f $ISO_FILE && -s $ISO_FILE" "0" "1"
	
	if [ $size_file = 1 ]; then
		run_com -Ee "rm -f $ISO_FILE >/dev/null"
		display -Ee  "During copying ISO image to file '$ISO_FILE'"
	fi
	
	echo_log "\n***** You can take out the USB\n"
	run_com -Ee "sleep 5"

	end_function
}

# Install_host_step_3.yml
########################################################################################

# Function for configuring network ipv6 
############################################

function config_ipv6()
{
	para_fun_l $*; start_function config_ipv6 "Configure network if ip6 has been defined"
	
	show_var -Ns IPADDR_HOST6
	
	if [[ -n $IPADDR_HOST6 ]]; then
		echo_log -l "IPADDR_HOST6=$IPADDR_HOST6"

		check_var -Ee DEFAULTGW6
		check_var -Ee PREFIX6
		check_var -Ee DNS6	

		run_com -Ee "nmcli -p con mod bond0 ipv6.addr ${IPADDR_HOST6}/${PREFIX6}" 
		run_com -Ee "nmcli -p con mod bond0 ipv6.addr ${IPADDR_HOST6}/${PREFIX6} ipv6.gateway ${DEFAULTGW6}"
		run_com -Ee "nmcli -p con mod bond0 ipv6.dns \"${DNS6}\""
		run_com -Ee "nmcli connection modify id bond0 connection.autoconnect yes"
	else
		echo_log -l "IPADDR_HOST6=$IPADDR_HOST6"

		echo_log "ipv4 has been defined only"
	fi

	end_function
}

# Function for configuring system
############################################

function config_dracut()
{
	para_fun_l $*; start_function config_dracut "Running dracut"
	
	run_com -Ee "dracut -v --force"

	old_cpu

	end_function
}

# Function for installing utilities 
############################################

function config_utilities()
{
    para_fun_l $*; start_function config_utilities "Install utilities"

	define_var -Ee root "/opt/pang/utilities"
	define_var -Ee tar "/usr/bin/tar -zxvf" 

	run_com -Ee "cd $root/openpyxl_install"
	run_com -Ee "$tar jdcal-1.0.tar.gz"
	run_com -Ee "cd $root/openpyxl_install/jdcal-1.0"
	run_com -Ee "python setup.py install"

	run_com -Ee "cd $root/openpyxl_install"
	run_com -Ee "$tar et_xmlfile-1.0.0.tar.gz"
	
	run_com -Ee "cd $root/openpyxl_install/et_xmlfile-1.0.0"
	run_com -Ee "python setup.py install"
	
	run_com -Ee "cd $root/openpyxl_install"
	run_com -Ee "$tar openpyxl-2.3.0-b1.tar.gz"
	run_com -Ee "cd $root/openpyxl_install/openpyxl-2.3.0-b1"
	run_com -Ee "python setup.py install"
  
    run_com -Ee "cd $root"
    run_com -Ee "$tar i40e-1.5.16.tar.gz"
    run_com -Ee "cd $root/i40e-1.5.16/src/"
	run_com -Ee "make -j 6"
	run_com -Ee "make install"
	run_com -Ee "modprobe -vr i40e"
	run_com -Ee "modprobe -v i40e"

    # fix locale
    run_com -Ee "localedef -i en_US -f UTF-8 en_US.UTF-8"

	end_function
}

#### deploy-grub.sh
########################################################################################

# Function for configure VM list
############################################

function config_vm_list()
{
	para_fun_l $*; start_function config_vm_list "Get MV list for installation"

	update_env_file TOTAL_MEMORY
	update_env_file TOTAL_CORES
	update_env_file TOTAL_NUMA
	update_env_file NUMA
	
	define_var -Ee vm_listFlag "0"
	define_var -Ee partition_sizeFlag "0"
	define_var -Ee one_numaFlag "0"

	var -Ee line_number "grep -n '^NUMA=' $env_file | awk -F':' '{print \$1}'"
	var -Ee last_line " wc -l $env_file | awk '{print \$1}'"
	var_if -Ee line_to_remove "$line_number != $last_line" "echo \"$(($line_number + 1))\""
	run_com_if -Ee "$line_number != $last_line" "cp $env_file $env_file.back"
	run_com_if -Ee "$line_number != $last_line" "sed -i '$line_to_remove,\$d' $env_file"
	run_com_if -Ee "-e $env_file.back" "grep 'IPADDR_GUEST=' $env_file.back >> $env_file"

	while true; do
		while true; do
			vm_list
		done

		check_support_multi_vm
		check_partition_size_opt

		[[ $vm_listFlag = 1 && $partition_sizeFlag = 1 && $one_numaFlag = 1 ]] && break			
	done

	replace_char_by_char_4_var_2_small -Ee VM_LIST "," "space"

	for VM_NAME in $vm_list; do
		virsh_stop
	done

	check_common_vars

	report_file

	end_function
}

function handle_celerity()
{
	para_fun_l $*; start_function handle_celerity "Handle celeriy types"

	if [[ $CELERITY = no ]]; then
		echo_log -s "handle_celerity(): CELERITY=$CELERITY No celerity on this host."; end_function; return
	fi

	if [[ $CELERITY_2_3_FLAG = 0 ]]; then
		display -A "Celerity VM includes one vm only. CELERITY_FLAG = 1 && CELERITY_2_3_FLAG = 0"; end_function; return
	fi
	
	display_if -Eefj "$TOTAL_NUMA -lt 2" "For selecting this option you need machine with 2 NUMA's"
	
	define_var_if -Ee PRE_VM_LIST "$CELERITY_2_3_FLAG = 1" "$VM_LIST"
	update_env_file PRE_VM_LIST
	
	update_env_file "$CELERITY_2_FLAG = 1" "VM_0=${CELERITY_2}_N0"
	update_env_file "$CELERITY_2_FLAG = 1" "VM_1=${CELERITY_2}_N1"
	var_if -Ee vm_celerity_1 "$CELERITY_3_FLAG = 1" "echo $CELERITY_3 | awk -F '_' '{print \$1}'"
	var_if -Ee vm_celerity_2 "$CELERITY_3_FLAG = 1" "echo $CELERITY_3 | awk -F '_' '{print \$3\"_\"\$4}'"
	update_env_file "$CELERITY_3_FLAG = 1" "VM_0=${vm_celerity_1}_N0"
	update_env_file "$CELERITY_3_FLAG = 1" "VM_1=${vm_celerity_2}_N1"
	
	reset_var -Ee pad_in_list
	define_var_if -Ee pad_in_list "$PADirector_FLAG = 1" ",$PAD"

	define_var -Ee VM_LIST "$VM_0,$VM_1$pad_in_list"
	update_env_file VM_LIST

	run_com -Ee "sleep 5"
	
	end_function
}

function vm_list()
{
	para_fun_l $*; start_function vm_list "Ask For VM install on host"

	while true; do
	
		define_var -Ee breakFlag "0"
		reset_var -Ee message_vm_list
		define_var -Ee vm_listFlag "0"

		reset_var -Ee PACache
		reset_var -Ee PALive
		reset_var -Ee PARapid
		reset_var -Ee PAQoE_Controller
		reset_var -Ee PARapid_x2
		reset_var -Ee PAQoE_Controller_x2
		reset_var -Ee PARapid_and_PAQoE_Controller
		reset_var -Ee PADirector
			
		whiptail --title "VM LIST: " --nocancel --checklist \
	"Please choose VM's" 30 50 11 \
	"PACache" " " OFF \
	"PALive" " " OFF \
	"PARapid" " " OFF \
	"PARapid_4" " " OFF \
	"PAQoE_Controller" " " OFF \
	"PARapid_x2" " " OFF \
	"PAQoE_Controller_x2" " " OFF \
	"PARapid_and_PAQoE_Controller" " " OFF \
	"PADirector" " " OFF \
	2>$ans_file

		var -Ee VM_LIST "cat $ans_file | sed -e 's/\"//g' -e 's/ /,/g'"
		echo_log "\nVM_LIST='$VM_LIST'"
		run_com -Ee "sleep 5"
		[[ -z $VM_LIST ]] && continue
		
		define_var_if_else -Ee PACache_FLAG "`echo $VM_LIST | grep -wc PACache` = 1" "1" "0"
		update_env_file PACache_FLAG
		define_var_if_else -Ee PALive_FLAG "`echo $VM_LIST | grep -wc PALive` = 1" "1" "0"
		update_env_file PALive_FLAG
		define_var_if_else -Ee PARapid_FLAG "`echo $VM_LIST | grep -wc PARapid` = 1" "1" "0"
		update_env_file PARapid_FLAG
		define_var_if_else -Ee PARapid_4_FLAG "`echo $VM_LIST | grep -wc PARapid_4` = 1" "1" "0"
		update_env_file PARapid_4_FLAG
		define_var_if_else -Ee PAQoE_Controller_FLAG "`echo $VM_LIST | grep -wc PAQoE_Controller` = 1" "1" "0"
		update_env_file PAQoE_Controller_FLAG
		define_var_if_else -Ee PARapid_x2_FLAG "`echo $VM_LIST | grep -wc PARapid_x2` = 1" "1" "0"
		update_env_file PARapid_x2_FLAG
		define_var_if_else -Ee PAQoE_Controller_x2_FLAG "`echo $VM_LIST | grep -wc PAQoE_Controller_x2` = 1" "1" "0"
		update_env_file PAQoE_Controller_x2_FLAG
		define_var_if_else -Ee PARapid_and_PAQoE_Controller_FLAG "`echo $VM_LIST | grep -wc PARapid_and_PAQoE_Controller` = 1" "1" "0"
		update_env_file PARapid_and_PAQoE_Controller_FLAG
		define_var_if_else -Ee PADirector_FLAG "`echo $VM_LIST | grep -wc PADirector` = 1" "1" "0"
		update_env_file PADirector_FLAG

		define_var_if -Ee PACache "$PACache_FLAG = 1" "PACache"
		define_var_if -Ee PALive "$PALive_FLAG = 1" "PALive"
		define_var_if -Ee PARapid "$PARapid_FLAG = 1" "PARapid"
		define_var_if -Ee PARapid_4 "$PARapid_4_FLAG = 1" "PARapid_4"
		define_var_if -Ee PAQoE_Controller "$PAQoE_Controller_FLAG = 1" "PAQoE_Controller"
		define_var_if -Ee PARapid_x2 "$PARapid_x2_FLAG = 1" "PARapid_x2"
		define_var_if -Ee PAQoE_Controller_x2 "$PAQoE_Controller_x2_FLAG = 1" "PAQoE_Controller_x2"
		define_var_if -Ee PARapid_and_PAQoE_Controller "$PARapid_and_PAQoE_Controller_FLAG = 1" "PARapid_and_PAQoE_Controller"
		define_var_if -Ee PADirector "$PADirector_FLAG = 1" "PADirector"

		var_if_else -Ee UB "$PACache_FLAG = 1 || $PALive_FLAG = 1" "echo $PACache$PALive" "echo no"
		update_env_file UB
		var_if_else -Ee CELERITY_1 "$PARapid_FLAG = 1 || $PARapid_4_FLAG = 1 || $PAQoE_Controller_FLAG = 1" "echo $PARapid$PARapid_4$PAQoE_Controller" "echo no"
		update_env_file CELERITY_1
		var_if_else -Ee CELERITY_2 "$PARapid_x2_FLAG = 1 || $PAQoE_Controller_x2_FLAG = 1" "echo $PARapid_x2$PAQoE_Controller_x2" "echo no"
		update_env_file CELERITY_2
		var_if_else -Ee CELERITY_3 "$PARapid_and_PAQoE_Controller_FLAG = 1" "echo $PARapid_and_PAQoE_Controller" "echo no"
		update_env_file CELERITY_3
		var_if_else -Ee CELERITY "$PARapid_FLAG = 1 || $PARapid_4_FLAG = 1 || $PAQoE_Controller_FLAG = 1 || $PARapid_x2_FLAG = 1 || $PAQoE_Controller_x2_FLAG = 1 || $PARapid_and_PAQoE_Controller_FLAG = 1 " "echo $PARapid$PARapid_4$PAQoE_Controller$PARapid_x2$PAQoE_Controller_x2$PARapid_and_PAQoE_Controller" "echo no"
		update_env_file CELERITY
		var_if_else -Ee PAD "$PADirector_FLAG = 1" "echo $PADirector" "echo no"
		update_env_file PAD
	
		define_var_if_else -Ee UB_FLAG "$PACache_FLAG = 1 || $PALive_FLAG = 1" "1" "0"
		update_env_file UB_FLAG
		define_var_if_else -Ee CELERITY_1_FLAG "$PARapid_FLAG = 1 || $PARapid_4_FLAG = 1 || $PAQoE_Controller_FLAG = 1" "1" "0"
		update_env_file CELERITY_1_FLAG
		define_var_if_else -Ee CELERITY_2_FLAG "$PARapid_x2_FLAG = 1 || $PAQoE_Controller_x2_FLAG = 1" "1" "0"
		update_env_file CELERITY_2_FLAG
		define_var_if_else -Ee CELERITY_3_FLAG "$PARapid_and_PAQoE_Controller_FLAG = 1" "1" "0"
		update_env_file CELERITY_3_FLAG
		define_var_if_else -Ee CELERITY_2_3_FLAG "$CELERITY_2_FLAG = 1 || $CELERITY_3_FLAG = 1" "1" "0"
		update_env_file CELERITY_2_3_FLAG
		define_var_if_else -Ee CELERITY_FLAG "$CELERITY_1_FLAG = 1 || $CELERITY_2_FLAG = 1 || $CELERITY_3_FLAG = 1" "1" "0"
		update_env_file CELERITY_FLAG
		define_var_if_else -Ee PAD_FLAG "$PADirector_FLAG = 1" "1" "0"
		update_env_file PAD_FLAG 

		define_var_if_else -Ee UB_ONLY "$VM_LIST = $UB" "yes" "no"
		update_env_file UB_ONLY
		define_var_if_else -Ee CELERITY_1_ONLY "$VM_LIST = $CELERITY_1" "yes" "no"
		update_env_file CELERITY_1_ONLY
		define_var_if_else -Ee CELERITY_2_ONLY "$VM_LIST = $CELERITY_2" "yes" "no"
		update_env_file CELERITY_2_ONLY
		define_var_if_else -Ee CELERITY_3_ONLY "$VM_LIST = $CELERITY_3" "yes" "no"
		update_env_file CELERITY_3_ONLY
		define_var_if_else -Ee CELERITY_2_3_ONLY "$CELERITY_2_ONLY = yes || $CELERITY_3_ONLY = yes" "yes" "no"
		update_env_file CELERITY_2_3_ONLY
		define_var_if_else -Ee CELERITY_ONLY "$CELERITY_1_ONLY = yes || $CELERITY_2_ONLY = yes || $CELERITY_3_ONLY = yes" "yes" "no"
		update_env_file CELERITY_ONLY
		define_var_if_else -Ee PAD_ONLY "$VM_LIST = $PAD" "yes" "no"
		update_env_file PAD_ONLY
	
		define_var_if_else -Ee UB_INCLUDES "$UB_FLAG = 1" "yes" "no"
		update_env_file UB_INCLUDES
		define_var_if_else -Ee CELERITY_1_INCLUDES "$CELERITY_1_FLAG = 1" "yes" "no"
		update_env_file CELERITY_1_INCLUDES
		define_var_if_else -Ee CELERITY_2_INCLUDES "$CELERITY_2_FLAG = 1" "yes" "no"
		update_env_file CELERITY_2_INCLUDES
		define_var_if_else -Ee CELERITY_3_INCLUDES "$CELERITY_3_FLAG = 1" "yes" "no"
		update_env_file CELERITY_3_INCLUDES
		define_var_if_else -Ee CELERITY_2_3_INCLUDES "$CELERITY_2_INCLUDES = yes || $CELERITY_3_INCLUDES = yes" "yes" "no"
		update_env_file CELERITY_2_3_INCLUDES
		define_var_if_else -Ee CELERITY_INCLUDES "$CELERITY_1_FLAG = 1 || $CELERITY_2_FLAG = 1 || $CELERITY_3_FLAG = 1" "yes" "no"
		update_env_file CELERITY_INCLUDES
		define_var_if_else -Ee PAD_INCLUDES "$PAD_FLAG = 1" "yes" "no"
		update_env_file PAD_INCLUDES

		define_var_if_else -Ee UB_CELERITY_INCLUDES "$UB_FLAG = 1 && $CELERITY_FLAG = 1 " "yes" "no"
		update_env_file UB_CELERITY_INCLUDES
		define_var_if_else -Ee UB_PAD_INCLUDES "$UB_FLAG = 1 && $PAD_FLAG = 1" "yes" "no"
		update_env_file UB_PAD_INCLUDES
		define_var_if_else -Ee CELERITY_PAD_INCLUDES "$CELERITY_FLAG = 1 && $PAD_FLAG = 1" "yes" "no"
		update_env_file CELERITY_PAD_INCLUDES
	
		define_var_if_else -Ee UB_CELERITY_PAD_INCLUDES "$UB_FLAG = 1 && $CELERITY_FLAG = 1 && $PAD_FLAG = 1" "yes" "no"
		update_env_file UB_CELERITY_PAD_INCLUDES
		define_var_if_else -Ee UB_OR_CELERITY_AND_PAD_INCLUDES "$VM_LIST = $UB,$PAD || $VM_LIST = $CELERITY,$PAD" "yes" "no"
		update_env_file UB_OR_CELERITY_AND_PAD_INCLUDES
		define_var_if_else -Ee CELERITY_2_AND_PAD_INCLUDES "$CELERITY_2_FLAG = 1 && $PAD_FLAG = 1" "yes" "no"
		update_env_file CELERITY_2_AND_PAD_INCLUDES
		define_var_if_else -Ee CELERITY_3_AND_PAD_INCLUDES "$CELERITY_3_FLAG = 1 && $PAD_FLAG = 1" "yes" "no"
		update_env_file CELERITY_3_AND_PAD_INCLUDES
		define_var_if_else -Ee CELERITY_2_3_AND_PAD_INCLUDES "$CELERITY_2_3_FLAG = 1 && $PAD_FLAG = 1" "yes" "no"
		update_env_file CELERITY_2_3_AND_PAD_INCLUDES
		define_var_if_else -Ee UB_OR_PARapid_4_INCLUDES "$UB_FLAG = 1 || $PARapid_4_FLAG = 1" "yes" "no"
		update_env_file UB_OR_PARapid_4_INCLUDES

		define_var_if_else -Ee UB_GROUP "$UB_FLAG = 1" "ub" "no"
		update_env_file UB_GROUP
		define_var_if_else -Ee CELERITY_1_GROUP "$CELERITY_1_FLAG = 1" "celerity_1" "no"
		update_env_file CELERITY_1_GROUP
		define_var_if_else -Ee CELERITY_2_GROUP "$CELERITY_2_FLAG = 1" "celerity_2" "no"
		update_env_file CELERITY_2_GROUP
		define_var_if_else -Ee CELERITY_3_GROUP "$CELERITY_3_FLAG = 1" "celerity_3" "no"
		update_env_file CELERITY_3_GROUP
		define_var_if_else -Ee CELERITY_2_3_GROUP "$CELERITY_2_3_FLAG = 1" "celerity_2_3" "no"
		update_env_file CELERITY_2_3_GROUP
		define_var_if_else -Ee CELERITY_GROUP "$CELERITY_1_GROUP = celerity_1 || $CELERITY_2_GROUP = celerity_2 || $CELERITY_3_GROUP = celerity_3" "celerity" "no"
		update_env_file CELERITY_GROUP
		define_var_if_else -Ee PAD_GROUP "$PAD_FLAG = 1" "pad" "no"
		update_env_file PAD_GROUP

		define_var_if_else -Ee ONE_NUMA_WITH_UB_AND_CELERITY "$NUMA = no && \"$CPU_MODEL\" = \"$ONE_NUMA_CPU_MODEL\" && $UB_FLAG = 1 && $CELERITY_1_FLAG = 1 && $PAD_FLAG = 0" "yes" "no"
		update_env_file ONE_NUMA_WITH_UB_AND_CELERITY
	
		var -Ee VM_LIST_GROUP "echo \"$UB_GROUP,$CELERITY_1_GROUP,$CELERITY_2_GROUP,$CELERITY_3_GROUP,$PAD_GROUP\" | sed -e 's/no//g' -e 's/ //g' | tr -s ',' | sed -e 's/^,//' -e 's/,\$//'"
		update_env_file VM_LIST_GROUP

		reset_var -Ee error_message

		if [[ $DMIDECODE_PLATFORM = OptiPlex ]]; then
			var_if_else -Ee celerity_only "`echo \"$UB_FLAG $PAD_FLAG\" | grep -c 1` = 1" "no" "yes"
			define_var_if -Ee error_message "$only_celerity = no" "On OptiPlex only celerity can be installed"
		fi

		echo_log -l "vm_list(): NUMA=$NUMA"

		if [[ $NUMA = no ]]; then
			define_var_if_else -Ee no_one_numa_with_ub_and_celerity "$ONE_NUMA_WITH_UB_AND_CELERITY = yes && \"$CPU_MODEL\" = \"$ONE_NUMA_CPU_MODEL\"" "yes" "no"
			define_var_if -Ee no_one_numa_with_ub_and_celerity "( $UB_FLAG = 1 && $CELERITY_1_FLAG = 0 ) || ($UB_FLAG = 0 && $CELERITY_1_FLAG = 1 )" "yes"
			define_var_if -Ee error_message "$no_one_numa_with_ub_and_celerity = no" "One NUMA ub and/or celerity only can be installed"
			define_var_if -Ee error_message "$CELERITY_2_3_FLAG = 1" "This option need 2 NUMA"
		fi
		
		define_var_if -Ee error_message "$UB_FLAG = 1 && $CELERITY_2_3_FLAG = 1" "VM_LIST=$VM_LIST . You can't choose '$UB' with '$CELERITY_2' or '$CELERITY_3'"
		define_var_if -Ee error_message "$UB_FLAG = 1 && $PARapid_4_FLAG = 1" "VM_LIST=$VM_LIST . Dosen't support this sclection"
		define_var_if -Ee error_message "$CELERITY_1_FLAG = 1 && $CELERITY_2_3_FLAG = 1" "VM_LIST=$VM_LIST . You can't choose '$CELERITY_1' with '$CELERITY_2' '$CELERITY_3'"
		define_var_if -Ee error_message "$CELERITY_2_FLAG = 1 && $CELERITY_3_FLAG = 1" "VM_LIST=$VM_LIST . You can't choose '$CELERITY_2' with '$CELERITY_3'"
		define_var_if -Ee error_message "$CELERITY_1_FLAG = 1 && $CELERITY_2_FLAG = 1 && $CELERITY_3_FLAG = 1" "VM_LIST=$VM_LIST . You can't choose '$CELERITY_1' '$CELERITY_2' with '$CELERITY_3'"
		define_var_if -Ee error_message "$PACache_FLAG = 1 && $PALive_FLAG = 1" "VM_LIST=$VM_LIST . You can choose one of 'PACache' 'PALive'"
		var -Ee all_celertiy "echo \"$(($PARapid_FLAG + $PARapid_4_FLAG + $PAQoE_Controller_FLAG))\"" 
		define_var_if -Ee error_message "$all_celertiy -gt 1" "VM_LIST=$VM_LIST . You need choose one of 'PARapid' 'PARapid_4' 'PAQoE_Controller'"
		define_var_if -Ee error_message "$PARapid_x2_FLAG = 1 && $PAQoE_Controller_x2_FLAG = 1" "VM_LIST=$VM_LIST . You can choose one of 'PARapid_x2' 'PAQoE_Controller_x2'"

		display_if -WjJ "sleep 5" "-n \"$error_message\"" "$error_message"
		define_var_if -Ee breakFlag "-n \"$error_message\"" "1"

		[[ -z $VM_LIST ]] && exit 1
		[[ $breakFlag = 1 ]] && continue ||  break
	done

	handle_celerity

	update_env_file VM_LIST
	
	define_var_if_else -Ee ONE_VM_INCLUDES "`echo $VM_LIST | grep -c ','` = 0" "yes" "no"
	update_env_file ONE_VM_INCLUDES
	define_var_if_else -Ee ONE_VM_WITHOUT_PAD_INCLUDES "`echo $VM_LIST | sed 's/,PADirector//' | grep -c ','` = 0" "yes" "no"
	update_env_file ONE_VM_WITHOUT_PAD_INCLUDES

	var -Ee VM_LIST_GROUP "echo \"$UB_GROUP,$CELERITY_1_GROUP,$CELERITY_2_GROUP,$CELERITY_3_GROUP,$PAD_GROUP\" | sed -e 's/no//g' -e 's/ //g' | tr -s ',' | sed -e 's/^,//' -e 's/,\$//'"
	update_env_file VM_LIST_GROUP

	define_var -Ee counter "1"
	replace_char_by_char_4_var_2_small -Ee VM_LIST "," "space"
	for vm in $vm_list; do
		case $counter in
			1) define_var -Ee num "FIRST" ;;
			2) define_var -Ee num "SECOND" ;;
			3) define_var -Ee num "THRID" ;;
		esac
		var -Ee counter "echo \"$(($counter + 1))\""
		var -Ee ${num}_VM "echo $vm"
		update_env_file ${num}_VM
	done

	define_var -Ee vm_listFlag "1"
	break

	end_function
}

function check_support_multi_vm()
{
	para_fun_l $*; start_function check_support_multi_vm "Check support multi VM on same machine"

	define_var -Ee min_cores  "12"
	define_var_if -Ee min_cores "$UB_CELERITY_PAD_INCLUDES = yes" "56"
	define_var_if -Ee min_cores "$DMIDECODE_PLATFORM = OptiPlex" "4"

	define_var -Ee min_memory "30"
	define_var_if -Ee min_memory "$UB_CELERITY_PAD_INCLUDES = yes" "120"
	define_var_if -Ee min_memory "$DMIDECODE_PLATFORM = OptiPlex" "7"

	define_var -Ee system_disk_type  "ssd_or_sas"
	define_var_if -Ee system_disk_type "$UB_CELERITY_PAD_INCLUDES = yes" "SSD"

	define_var_if_else -Ee cores_checkFlag "$TOTAL_CORES -ge $min_cores" "0" "1"
	display_if_not -Ef "$cores_checkFlag = 0" "Number of cores is need to be at least '$min_cores'"

	define_var_if_else -Ee memory_checkFlag "$TOTAL_MEMORY -ge $min_memory" "0" "1"
	display_if_not -Ef "$memory_checkFlag = 0" "Total memory is need to be at least '${min_memory}G'"

	define_var -Ee ssd_checkFlag "1"
	define_var_if -Ee ssd_checkFlag "$system_disk_type = $SYSTEM_DISK_TYPE" "0"
	define_var_if -Ee ssd_checkFlag "$system_disk_type = ssd_or_sas" "0"
	
	display_if -Ef "$ssd_checkFlag = 1" "System type disk is '$SYSTEM_DISK_TYPE' need to be 'SSD'"

	define_var_if_else -Ee numa_checkFlag "$NUMA = no" "1" "0"
	define_var_if -Ee numa_checkFlag "$ONE_NUMA_WITH_UB_AND_CELERITY = yes || $ONE_VM_INCLUDES = yes" "0"
	define_var_if -Ee numa_checkFlag "$DMIDECODE_PLATFORM = OptiPlex" "0"
	display_if -Ef "sleep 5" "$numa_checkFlag = 1" "No NUMA on host. Combination is not supported"
	define_var_if -Ee one_numaFlag "$numa_checkFlag = 0" "1"

	[[ $cores_checkFlag = 1 || $memory_checkFlag = 1 || $ssd_checkFlag = 1 ]] && ask4only_yes_or_exit_error "See problems"
	
	end_function
}

function check_partition_size_opt()
{
	para_fun_l $*; start_function check_partition_size_opt "Check partition /opt fit"

	define_var -Ee sum_partition "0"
	var -Ee partition_size_opt "df -h | grep /opt | awk '{print \$4}'"
	define_var_if_else -Ee room_type "`echo $partition_size_opt | grep -c T` = 1" "tera" "giga"
	var_if -Ee partition_size_opt "$room_type = giga" "echo $partition_size_opt | awk -F '.' '{print \$1}' | tr -d 'G'"
	var_if -Ee partition_size_opt "$room_type = tera" "echo $partition_size_opt | tr -d 'T' | tr -d '.'"
	var_if -Ee partition_size_opt "$room_type = tera" "echo \"$(($partition_size_opt * 1000))\""

	replace_char_by_char_4_var_2_small -Ee VM_LIST_GROUP "," "space"

	for vm in $vm_list_group; do
		case $vm in
			ub) 			define_var_if_else -Ee partition_size "$ONE_VM_INCLUDES = yes" "170" "330" ;;
			celerity_1)		define_var_if_else -Ee partition_size "$ONE_VM_INCLUDES = yes" "170" "210" ;;
			celerity_2|celerity_3)		define_var -Ee partition_size "420" ;;
			pad)			define_var -Ee partition_size "80" ;;
		esac
		echo_log "VM size='$partition_size'"
		var -Ee sum_partition "echo \"$(($sum_partition + $partition_size))\""
	done

	define_var_if_else -Ee size_ok "$sum_partition -gt $partition_size_opt" "bad" "good"
	display_if -Wfj "sleep 5" "$size_ok = bad" "Partition /opt is not big enough, need '${sum_partition}GB' and system disk is '${partition_size_opt}GB'"
	define_var_if -Ee partition_sizeFlag "$size_ok = good" "1"

	end_function
}

function check_function_vars()
{
	para_fun_l $*; start_function check_function_vars "Check vars for function '$1'"
	
	case $1 in
		config_numa_id_4_vm)				check_var_loop_if -Ee "$CELERITY_2_3_FLAG = 1" VM_0 VM_1 ;;
		config_host_isol_cores)				check_var_if -Ee NUM_ISOL_CORES "$UB_INCLUDES = yes" ;;
		config_grub)						check_var_loop_if -Ee "$UB_INCLUDES = yes" HOST_ISOL_CORES_ID HOST_ISOL_HYPER_CORES_ID ;;
		config_xml_skeleton)				check_var -Ee GUEST_CORES
											check_var_loop_if -Ee "$UB_INCLUDES = yes" HOST_ISOL_CORES_ID HOST_ISOL_HYPER_CORES_ID
											check_var_if -Ee NUMA_0_MEM "$NUMA_ID = 0"
											check_var_if -Ee NUMA_1_MEM "$NUMA_ID = 1";;				
		config_network_4_vm)				check_var -Ee IPV_MODE ;;
		config_vm_system_disk)				check_var -Ee VM_SIZE ;;
		config_local_cdrom)					check_var -Ee ISO_FILE ;;
		config_local_nics)					check_var_if -Ee DATA_INTERFACES "$VM_NAME_GROUP != PAD" ;;
		config_prepare_data_disks_list)		check_var_if -Ee DATA_DISKS_SLOT_LIST "$VM_NAME = PACache"  ;;
		config_prepare_webcache_disks_list)	check_var_loop_if -Ee "$VM_NAME = PACache" DATA_DISKS_SLOT_LIST WEBCACHE_DISKS_SLOT_LIST ;;							
		config_data_webcache_disk)			check_var_loop_if -Ee "$VM_NAME = PACache" DATA_DISKS_SLOT_LIST WEBCACHE_DISKS_SLOT_LIST ;;
		config_local_storage_data)			check_var_if -Ee DATA_DISKS_SLOT_LIST "$VM_NAME = PACache" DATA_DISKS_SLOT_LIST ;;
		config_local_storage_webcache)		check_var_loop_if -Ee "$VM_NAME = PACache" VIRTUAL_WEBCACHE_DISKS_LIST VD_WEBCACHE ;;
		config_ssd_partition_for_vd) 		check_var_if -Ee WEBCACHE_DISKS_SLOT_LIST "$VM_NAME_GROUP = UB" ;;
		config_fast_path)					check_var_loop_if -Ee "$VM_NAME_GROUP = UB || $VM_NAME = PARapid_4" GUEST_ISOL_CORES_ID DATA_INTERFACES MUXERS ;;
	esac

	end_function
}

function check_common_vars()
{	
	para_fun_l $*; start_function check_common_vars "Check common vars"

	check_var_loop -Ee DMIDECODE_PLATFORM TOTAL_MEMORY TOTAL_CORES NUMA CPU_MODEL
	check_var_loop -Ee _FSTAB DIR_NIC IPV_MODE MGMT_GUEST SYSTEM_DISK_TYPE VM_IMG_DIR

	define_var_if_else -Ee VM_LIST_GROUP_exists "-n \"$VM_LIST_GROUP\"" "yes" "no"
	if [[ $VM_LIST_GROUP_exists = yes ]]; then
		check_var_loop -Ee VM_LIST_GROUP VM_LIST
		check_var_loop -Ee PACache_FLAG PALive_FLAG PARapid_FLAG PAQoE_Controller_FLAG PADirector_FLAG
		check_var_loop -Ee UB_FLAG CELERITY_1_FLAG CELERITY_2_FLAG CELERITY_3_FLAG CELERITY_2_3_FLAG PAD_FLAG
		check_var_loop -Ee UB CELERITY_1 CELERITY_2 CELERITY_3 CELERITY PAD
		check_var_loop -Ee ONE_NUMA_WITH_UB_AND_CELERITY ONE_VM_INCLUDES ONE_VM_WITHOUT_PAD_INCLUDES UB_OR_CELERITY_AND_PAD_INCLUDES
		check_var_loop -Ee UB_ONLY CELERITY_1_ONLY CELERITY_2_ONLY CELERITY_3_ONLY CELERITY_2_3_ONLY PAD_ONLY
		check_var_loop -Ee UB_INCLUDES PAD_INCLUDES UB_PAD_INCLUDES UB_PAD_INCLUDES CELERITY_PAD_INCLUDES UB_CELERITY_PAD_INCLUDES UB_OR_PARapid_4_INCLUDES
		check_var_loop -Ee CELERITY_INCLUDES CELERITY_1_INCLUDES CELERITY_2_INCLUDES CELERITY_3_INCLUDES CELERITY_2_3_INCLUDES
		check_var_loop -Ee UB_GROUP PAD_GROUP
		check_var_loop -Ee CELERITY_GROUP CELERITY_1_GROUP CELERITY_2_GROUP CELERITY_3_GROUP CELERITY_2_3_GROUP
	fi

	define_var_if_else -Ee VM_NAME_GROUP_exists "-n \"$VM_NAME_GROUP\"" "yes" "no"
	if [[ $VM_NAME_GROUP_exists = yes ]]; then
		check_var_loop -Ee VM_NAME_GROUP PRE_VM VM_NAME
		check_var_loop_if -Ee "CELERITY_2_3_FLAG = 1" "VM_0" "VM_1" "PRE_VM_LIST"
		check_var_if -Ee HUGEPG1 "$NUMA = yes"
	fi

	define_var_if_else -Ee HOST_CORES_exists "-n \"$HOST_CORES\"" "yes" "no"
	if [[ $HOST_CORES_exists = yes ]]; then
		check_var_loop -Ee HOST_CORES HOST_NUMA_0_CORES HOST_NUMA_0_HYPER_CORES
		check_var_loop_if -Ee "$NUMA = 2" HOST_NUMA_1_HYPER_CORES HOST_NUMA_1_CORES
	fi

	define_var_if_else -Ee NUMA_ID_exists "-n \"$NUMA_ID\"" "yes" "no"
	if [[ $NUMA_ID_exists = yes ]]; then
		check_var -Ee NUMA_ID
		check_var -Ee ${PRE_VM}DATA_INTERFACES
	fi
		
	define_var_if_else -Ee DATA_INTERFACES_exists "-n \"$DATA_INTERFACES\"" "yes" "no"
	if [[ $DATA_INTERFACES_exists = yes ]]; then
		check_var -Ee ${PRE_VM}DATA_INTERFACES
		check_var -Ee ${PRE_VM}VM_SIZE
		check_var -Ee ${PRE_VM}NUMA_ID
	fi

	end_function
}

function report_file()
{
	para_fun_l $*; start_function report_file "Report file"
	
	export_env

	echo_log -r "DATE `date`\n"
	echo_log_var -r "IPADDR_HOST"
	echo_log -r "\n/etc/PA-release-ISO"
	run_com -Ee "cat /etc/PA-release-ISO >> $REPORT"
	echo_log_var -rj DMIDECODE_PLATFORM
	echo_log_var -r ISO_VERSION
	echo_log_var -r PANG_VERSION
	echo_log_var -r CPU_MODEL
	echo_log_var -r TOTAL_MEMORY 
	echo_log_var -r TOTAL_CORES
	echo_log_var -r TOTAL_NUMA
	echo_log_var -rjJ VM_LIST

	end_function
}

# Function for geting info on host
############################################

function config_host_cores()
{
	para_fun_l $*; start_function config_host_cores "Get information on cores host"

	run_com -Ee "$lstopo_no_graphics | grep '(P#' > $temp"
	show_file -Ee $temp "Cores on host"

	define_var -Ee muma_tr "tr '\n' ',' | sed 's/,\$//'"
	define_var -Ee sub_numa_grep "grep -v NUMANode"
	
	if [[ $NUMA = no ]]; then
		define_var -Ee numa_grep "cat"
	else
		define_var -Ee numa_grep "sed -n '/NUMANode L#0/,/NUMANode L#1/p'"
	fi

	host_core_hyper_list 0
	host_core_and_hyper_core_list 0
	
	if [[ $NUMA = yes ]]; then
		define_var -Ee numa_grep "sed -n '/NUMANode L#1/,\\\$p'"

		host_core_hyper_list 1
		host_core_and_hyper_core_list 1
	fi
	
	var -Ee HOST_CORES "echo \"$HOST_NUMA_0_CORES,$HOST_NUMA_1_CORES,$HOST_NUMA_0_HYPER_CORES,$HOST_NUMA_1_HYPER_CORES\" | sed -e 's/,,/,/g' -e 's/,\$//'"
	update_env_file HOST_CORES	
	echo_log_var -r HOST_CORES

	var -Ee HOST_CORES_AND_HYPER_CORES "echo \"$HOST_NUMA_0_CORES_AND_HYPER_CORES,$HOST_NUMA_1_CORES_AND_HYPER_CORES\" | sed -e 's/,,/,/g' -e 's/,\$//'"
	update_env_file HOST_CORES_AND_HYPER_CORES	
	echo_log_var -r HOST_CORES_AND_HYPER_CORES

	end_function
}

function host_core_hyper_list()
{
	para_fun_l $*; start_function host_core_hyper_list "List cores and hyper on NUMA"

	define_var -Ee numa_num "$1"

	define_var -Ee second_sub_numa_grep "awk -F '#' '{print \\\$NF}' | sed 's/)//'"
	
	var -Ee HOST_NUMA_${numa_num}_CORES "$numa_grep $temp | $sub_numa_grep | $second_sub_numa_grep | sed -n 1~2p | $muma_tr"
	update_env_file HOST_NUMA_${numa_num}_CORES
	echo_log_var -r HOST_NUMA_${numa_num}_CORES

	var -Ee HOST_NUMA_${numa_num}_HYPER_CORES "$numa_grep $temp | $sub_numa_grep | $second_sub_numa_grep | sed -n 2~2p | $muma_tr"
	update_env_file HOST_NUMA_${numa_num}_HYPER_CORES
	echo_log_var -r HOST_NUMA_${numa_num}_HYPER_CORES
	
	end_function
}

function host_core_and_hyper_core_list()
{
	para_fun_l $*; start_function host_core_and_hyper_core_list "Merage cores and hyper on NUMA"

	define_var -Ee numa_num "$1"
	var -Ee cores "eval \"echo \"\$HOST_NUMA_${numa_num}_CORES\"\""
	var -Ee hypers "eval \"echo \"\$HOST_NUMA_${numa_num}_HYPER_CORES\"\""
	run_com -Ee "echo $cores | tr ',' '\n' > $temp1"
	run_com -Ee "echo $hypers | tr ',' '\n' > $temp2"
	var -Ee cores_hypers "paste $temp1 $temp2 | tr '\t' ',' | tr '\n' ',' | sed 's/,\$//'"

	update_env_file HOST_NUMA_${numa_num}_CORES_AND_HYPER_CORES=$cores_hypers
	echo_log_var -r HOST_NUMA_${numa_num}_CORES_AND_HYPER_CORES

	end_function
}

############################################

function config_numa_id_4_vm()
{
	para_fun_l $*; start_function config_numa_id_4_vm "Get NUMA id for vm"

	echo_log -l "NUMA=$NUMA"

	if [[ $NUMA = no ]]; then
		replace_char_by_char_4_var_2_small -Ee VM_LIST "," "space"
		for vm_name in $vm_list; do
			pre_vm $vm_name
			update_env_file "${PRE_VM}NUMA_ID=0"
		done
		end_function; return
	fi

	echo_log -l "Case VM_LIST_GROUP=$VM_LIST_GROUP"

	case $VM_LIST_GROUP in
		ub|ub,pad)
			display -A "NUMA for 'ub' only will be defined later"
		;;
		ub,celerity_1|ub,celerity_1,pad)
			update_env_file "$VM_NAME_GROUP = UB" "${PRE_VM}NUMA_ID=1"
			update_env_file "UB_NUMA_ID=1"
			echo_log_var -r UB_NUMA_ID

			pre_vm $CELERITY
			update_env_file "${PRE_VM}NUMA_ID=0"
			echo_log_var -r ${PRE_VM}NUMA_ID
		;;
		celerity_1|celerity_1,pad)
			display -A "NUMA for 'celerity' only will be defined later"
		;;
		celerity2_3|celerity2_3,pad)
			update_env_file "${VM_0}_NUMA_ID=0"
			echo_log_var -r ${VM_0}_NUMA_ID

			update_env_file "${VM_1}_NUMA_ID=1"
			echo_log_var -r ${VM_1}_NUMA_ID
		;;
		pad)
			display -A "Will not run on 'pad' installation only"
		;;
	esac
 
	end_function
}

# Function for selecting data NICs
############################################

function config_data_nics()
{
	para_fun_l $*; start_function config_data_nics "Choose interfaces for data VM VM=$VM_NAME"

	echo_log -l "For loop VM_LIST=$VM_LIST"

	replace_char_by_char_4_var_2_small -Ee VM_LIST "," "space"
	for vm in $vm_list; do
		if [[ $vm = PADirector ]]; then 
			display -A "No data nics on 'PADirector'"
			end_function; return
		fi

		pre_vm_name $vm

		data_nics
		numa_id_4_ub_celerity
	done

	clean_variables

	end_function
}

function data_nics()
{
	para_fun_l $*; start_function data_nics "Choose interfaces for data VM MV=$VM_NAME"

	create_nics_file bond0

	echo_log -l "data_nics(): ONE_NUMA_WITH_UB_AND_CELERITY=$ONE_NUMA_WITH_UB_AND_CELERITY"

	if [[ $ONE_NUMA_WITH_UB_AND_CELERITY = yes ]]; then

		echo_log -l "data_nics(): VM_NAME_GROUP=$VM_NAME_GROUP"

		if [[ $VM_NAME_GROUP = CELERITY_1 ]]; then
			pre_vm_name $UB
			var -Ee interfaces "eval \"echo \$${PRE_VM}DATA_INTERFACES\""
			replace_char_by_char_4_var -Ee interfaces "," "space"
			for interface in $interfaces ; do
				run_com -Ee "sed -i '/$interface/d' $temp_nics"
			done
			pre_vm_name $CELERITY_1
		fi
	else
		reset_var -Ee numa_id_remove
		
		define_var_if_else -Ee numa_id_exists "$VM_NAME_GROUP = UB && $CELERITY_FLAG = 1" "yes" "no"
		define_var_if -Ee numa_id_remove "$numa_id_exists = yes" "0"

		define_var_if_else -Ee numa_id_exists "$VM_NAME_GROUP = CELERITY_1 && $UB_FLAG = 1" "yes" "no"
		define_var_if -Ee numa_id_remove "$numa_id_exists = yes" "1"

		define_var_if -Ee numa_id_remove "-n \"$VM_0\" && X$VM_NAME = X$VM_0" "1"
		define_var_if -Ee numa_id_remove "-n \"$VM_1\" && X$VM_NAME = X$VM_1" "0"

		run_com_if -Ee "-n \"$numa_id_remove\"" "sed -i '/_$numa_id_remove/d' $temp_nics"
	fi

	run_com -Ee "sed -i '/eno/d' $temp_nics"
	run_com -Ee "sed -i '/em/d' $temp_nics"
	display_if_not -Ee "-s $temp_nics" "No data nic card on for selected NUMA"
	show_file -Eel $temp_nics "For selecting nics"

	while true; do
		
		whiptail --title "VM: '$VM_NAME'" --nocancel --checklist "Please choose network cards for DATA" 30 50 20 `cat $temp_nics` 2>$ans_file
		var -Ee DATA_INTERFACES "cat $ans_file | sed -e 's/\"//g' -e 's/ /,/g'"
		check_nics_same_numaFlag=0
		check_nic_on_same_numa
		[[ -n $DATA_INTERFACES && $check_nics_same_numaFlag = 0 ]] && break
	done

	update_env_file "${PRE_VM}DATA_INTERFACES=$DATA_INTERFACES"
	echo_log_var -r ${PRE_VM}DATA_INTERFACES

	end_function
}

function check_nic_on_same_numa()
{
	para_fun_l $*; start_function check_nic_on_same_numa "Check that selected nics on same NUMA"

	var -Ee data_interfaces "echo $DATA_INTERFACES | tr ',' '|'"
	var -N numa_0 "egrep \"$data_interfaces\" $temp_nics | grep -c '_0_'"
	var -N numa_1 "egrep \"$data_interfaces\" $temp_nics | grep -c '_1_'"	

	if [[ $numa_0 != 0 && $numa_1 != 0 ]]; then
		display -Wf "sleep 5" "Nic cards not on same NUMA"
		define_var -Ee check_nics_same_numaFlag "1"
	else
		define_var_if_else -Ee ${PRE_VM}NUMA_ID "$numa_0 = 1" "0" "1"
	fi

	update_env_file "$VM_NAME_GROUP = UB" "UB_NUMA_ID=${PRE_VM}NUMA_ID"
	update_env_file ${PRE_VM}NUMA_ID

	end_function
}

############################################

function numa_id_4_ub_celerity()
{
	para_fun_l $*; start_function  "Get NUMA id for ub or celerity"

	var -Ee interface_grep "echo $DATA_INTERFACES | sed 's/,/|/g'"

	var -N numa0_nic_count "$lstopo_no_graphics | sed -n '/NUMANode L#0/,/NUMANode L#1/p' | egrep -c \"$interface_grep\""
	var -N numa1_nic_count "$lstopo_no_graphics | sed -n '/NUMANode L#1/,\$p' | egrep -c \"$interface_grep\""

	var_if_else -Ee NUMA_ID "$numa1_nic_count -gt $numa0_nic_count" "echo 1" " echo 0"
	
	update_env_file "${PRE_VM}NUMA_ID=$NUMA_ID"
	update_env_file "$VM_NAME_GROUP = UB" "UB_NUMA_ID=$NUMA_ID"
	echo_log_var -r ${PRE_VM}NUMA_ID

	end_function
}

# Install_grub_step_1.yml
########################################################################################

# Function for fstab to disable fsck on celerity optiplex
############################################

function config_update_fstab()
{
	para_fun_l $*; start_function config_update_fstab "Update the fstab on Celerity OptiPlex platform"

	if [[ $CELERITY_FLAG = 1 && $DMIDECODE_PLATFORM = OptiPlex ]]; then
		echo_log "Celerity on Dell OptiPlex platform detected, configuring not to fsck on boot"

		run_com -Ee "cp /etc/fstab /etc/fstab.optiplex.bak"
		replace_str_4_file -Ee $_FSTAB "1 1" "1 0"
		replace_str_4_file -Ee $_FSTAB "1 2" "1 0"
		run_com -Ee "mount -l -t ext4,ext3,ext2 | cut -d' ' -f1 | xargs -i tune2fs -T now {}"
		run_com -Ee "mount -l -t ext4,ext3,ext2 | cut -d' ' -f1 | xargs -i tune2fs -c 0 -i 0 {}"
	else

		echo_log "For OptiPlex platform only"
	fi

	end_function
}

# Function for choosing product
############################################

function config_product()
{
	para_fun_l $*; start_function config_product "Select 'PRODUCT' 'NUM_ISOL_CORES' and 'MUXERS'"
	
	if [[ $UB_OR_PARapid_4_INCLUDES = no ]]; then
		display -A "Run on 'ub' installation only UB_OR_PARapid_4_INCLUDES=$UB_OR_PARapid_4_INCLUDES"; end_function; return
	fi

	define_var -Ee PRODUCT "CORES_6_MUXERS_2"

	define_var -Ee cpu_grep "2680 v4|2695 v3"
	define_var_if_else -Ee check_output_40G "$VM_LIST_GROUP = ub && `lscpu | egrep -c "$cpu_grep"` = 1 && $TOTAL_MEMORY -ge 125" "yes" "no"
	if [[ $check_output_40G = yes ]]; then
		get_disks_list
		define_var_if_else -Ee output_40G "`grep -c SAS $disks_file` = 0" "yes" "no"
		define_var_if -Ee PRODUCT "$output_40G = yes" "CORES_8_MUXERS_2"
	fi

	var_if_else -Ee num_cores "$UB_CELERITY_INCLUDES = yes" "echo \"$(($TOTAL_CORES / 2))\"" "echo $TOTAL_CORES"
	define_var_if -Ee PRODUCT "$num_cores -le 32" "CORES_4_MUXERS_1"
	define_var_if -Ee PRODUCT "$num_cores -le 16" "CORES_2_MUXERS_1"
	update_env_file PRODUCT
	echo_log_var -r PRODUCT

	var -Ee NUM_ISOL_CORES "echo $PRODUCT | awk -F_ '{print \$2}'"
	update_env_file NUM_ISOL_CORES
	echo_log_var -r NUM_ISOL_CORES

	var -Ee MUXERS "echo $PRODUCT | awk -F_ '{print \$4}'"
	update_env_file MUXERS
	echo_log_var -r MUXERS

	end_function
}

function config_host_isol_cores()
{
	para_fun_l $*; start_function config_host_isol_cores "Configure host isolated cores"
	
	if [[ $UB_OR_PARapid_4_INCLUDES = no ]]; then
		display -A "Run on 'ub' installation only"; end_function; return
	fi

	define_var_if_else -Ee VM_NAME "$UB = no && $CELERITY = PARapid_4" "PARapid_4" "$UB" 
	pre_vm $VM_NAME

	get_isolated_cores $NUMA_ID $NUM_ISOL_CORES CORES
	get_isolated_cores $NUMA_ID $NUM_ISOL_CORES HYPER_CORES
	
	var -Ee HOST_ISOL_CORES_ID "eval \"echo \"\$HOST_NUMA_${NUMA_ID}_ISOL_CORES\"\""
	update_env_file HOST_ISOL_CORES_ID
	echo_log_var -r HOST_ISOL_CORES_ID

	var -Ee HOST_ISOL_HYPER_CORES_ID "eval \"echo \"\$HOST_NUMA_${NUMA_ID}_ISOL_HYPER_CORES\"\""
	update_env_file HOST_ISOL_HYPER_CORES_ID
	echo_log_var -r HOST_ISOL_HYPER_CORES_ID
	
	clean_variables

	end_function
}

function get_isolated_cores()
{
	para_fun_l $*; start_function get_isolated_cores "Configure host isolated cores"
	
	define_var -Eec numa_id $1
	define_var -Eec num_isol_cores $2
	define_var -Eec type_cores $3
	
	define_var -Eec name_cores "HOST_NUMA_${numa_id}_$type_cores"
	define_var -Eec name_isol_cores "HOST_NUMA_${numa_id}_ISOL_$type_cores"
	var -Ee cores_list "eval \"echo \$$name_cores\""
	run_com -Ee "echo $cores_list | tr ',' '\n' > $temp1"
	run_com -Ee "tac $temp1 > $temp"
	var -Ee cores_list "cat  $temp | tr '\n' ' '"
	
	reset_var -Ee cores
	for core in $cores_list; do
		var -Ee cores "echo \"$cores$core,\""
		var -Ee num_isol_cores "echo \"$(($num_isol_cores - 1))\""
		[[ $num_isol_cores = 0 ]] && break
	done
	
	var -Ee cores "echo $cores | sed 's/,\$//'"
	run_com -Ee "echo $cores | tr ',' '\n' > $temp1"
	run_com -Ee "tac $temp1 > $temp"
	var -Ee cores "cat $temp | tr '\n' ',' | sed 's/,\$//'"
	
	var -Ee $name_isol_cores "echo $cores"
	update_env_file $name_isol_cores
	
	end_function
}

# Function for configure grub
############################################

function config_grub()
{
	para_fun_l $*; start_function config_grub "Configure grub"

	echo_log -l "config_grub(): UB_OR_PARapid_4_INCLUDES=$UB_OR_PARapid_4_INCLUDES"

	if [[ $UB_OR_PARapid_4_INCLUDES = no ]]; then
		reset_var -Ee isol
		reset_var -Ee nohz_full
		reset_var -Ee rcu_nocbs
		reset_var -Ee processor_max_cstate
		reset_var -Ee intel_idle_max_cstate
	else
		define_var -Ee isol "$HOST_ISOL_CORES_ID,$HOST_ISOL_HYPER_CORES_ID"
		define_var -Ee isolcpus "isolcpus=$isol"
		define_var -Ee nohz_full "nohz_full=$isol"
		define_var -Ee rcu_nocbs "rcu_nocbs=$isol"
		define_var -Ee processor_max_cstate "processor.max_cstate=1"
		define_var -Ee intel_idle_max_cstate "intel_idle.max_cstate=0"
	fi

	define_var -Ee grub "/boot/grub2/grub.cfg"
	define_var -Ee default_grub "/etc/default/grub"
	var -Ee line_cmdline "cat /proc/cmdline"

	define_var -Ee grub_start "GRUB_CMDLINE_LINUX="
	define_var -Ee part1 "console=ttyS1,115200n8 console=tty0 textmode=1 iommu=pt intel_iommu=on"
	# add to abpve "vfio_iommu_type1.allow_unsafe_interrupts=1" to support old hardware
	define_var -Ee part2 "nosplash audit=0 transparent_hugepage=never clocksource=tsc"
	define_var -Ee part3 "vconsole.keymap=us crashkernel=auto vconsole.font=latarcyrheb-sun16 verbose nmi_watchdog=0"
	define_var_if -Ee part4 "$UB_OR_PARapid_4_INCLUDES = yes " "XX$isolcpus $nohz_full $rcu_nocbs $processor_max_cstate $intel_idle_max_cstate"
	
	define_var -Ee new_grub_line "$grub_start\\\"$part1 $part2 $part3 $part4\\\""

    run_com -Ee "cp $default_grub $default_grub.bak.`date +%Y-%m-%d:%H:%M:%S`"
	
    replace_str_4_file -Ee $default_grub "^${grub_start}.*" "$new_grub_line"

	run_com -Ee "grub2-mkconfig -o $grub"

	show_file -Ees $grub "Grub file"

	end_function
}

# Function for handling memory hugepages
############################################

function config_hugepages()
{
	para_fun_l $*; start_function config_hugepages "Configure HUGEPAGE on host"

	define_var -Ee rc_local "/etc/rc.d/rc.local"
	
	if [[ $DMIDECODE_PLATFORM = OptiPlex ]]; then
		echo_log -l "config_hugepages(): DMIDECODE_PLATFORM=$DMIDECODE_PLATFORM"

		define_var -Ee system_memory "500"
		var -Ee memory_hugepages "echo \"$(($TOTAL_MEMORY * 1024 - $system_memory))\""
		var -Ee HUGEPG0 "echo \"$(($memory_hugepages / 2))\""

		update_env_file HUGEPG0
		echo_log_var -rs HUGEPG0

		define_var -Ee HUGEPG1 "0"
		update_env_file HUGEPG1		
	else
		echo_log -l "config_hugepages(): DMIDECODE_PLATFORM=$DMIDECODE_PLATFORM"

		define_var -Ee system_memory "8"
		define_var_if -Ee system_memory "$TOTAL_MEMORY -lt 64" "6"
		define_var_if -Ee system_memory "$TOTAL_MEMORY -lt 32" "3"
		show_var -Ee system_memory
	
		var -Ee memory_hugepages "echo \"$(($TOTAL_MEMORY - $system_memory))\""
		var -Ee num_hugepages "echo \"$(($memory_hugepages * 1024 / 2))\""

		var_if_else -Ee HUGEPG0 "$NUMA = yes" "echo \"$(($num_hugepages / 2))\"" "echo \"$num_hugepages\""
		update_env_file HUGEPG0
		define_var_if_else -Ee HUGEPG1 "$NUMA = yes" "$HUGEPG0" "0"
		update_env_file HUGEPG1
	fi
	echo_log_var -rs HUGEPG0
	echo_log_var -rs HUGEPG1
		
	for i in 0 1; do
		var -Ee h "eval echo \$HUGEPG$i"
		define_var -Ee f "/sys/devices/system/node/node$i/hugepages/hugepages-2048kB/nr_hugepages"
		replace_str_4_file -Ee $rc_local "^echo .* $f" "echo $h > $f"
	done			

	show_file -Eel $rc_local

	end_function
}

#### deploy-guest.sh
########################################################################################

# Function for configure VM and host addresses
############################################

function config_ub_celerity_pad()
{
	para_fun_l $*; start_function config_ub_celerity_pad "Which VM to install"

	var -N dir_qcow2_exists "ls $VM_IMG_DIR | grep -c qcow2"
	
	if [[ $dir_qcow2_exists = 0 || ! -e /usr/bin/virsh ]]; then
		define_var -Ee message_list_vm "No any VM on HOST"
	else
		config_show_vm_on_host silent
	fi

	while true; do

		whiptail --title "$message_list_vm" --menu "Choose VM for installation/create xml:" 30 70 12 \
			"1" "PACache" \
			"2" "PALive"  \
			"3" "PARapid" \
			"4" "PARapid_4" \
			"5" "PAQoE_Controller" \
			"6" "Pair_1 PARapid_x2_N0" \
			"7" "Pair_2 PARapid_x2_N1" \
			"8" "Pair_1 PAQoE_Controller_x2_N0" \
			"9" "Pair_2 PAQoE_Controller_x2_N1" \
			"10" "Pair_1 PARapid_N0" \
			"11" "Pair_2 PAQoE_Controller_N1" \
			"12" "PADirector" \
			2>$ans_file

		var -Eec option_num "cat $ans_file"
 
		define_var_if -Ee VM_NAME "$option_num = 1" "PACache"
		define_var_if -Ee VM_NAME "$option_num = 2" "PALive"
		define_var_if -Ee VM_NAME "$option_num = 3" "PARapid"
		define_var_if -Ee VM_NAME "$option_num = 4" "PARapid_4"
		define_var_if -Ee VM_NAME "$option_num = 5" "PAQoE_Controller"
		define_var_if -Ee VM_NAME "$option_num = 6" "PARapid_x2_N0"
		define_var_if -Ee VM_NAME "$option_num = 7" "PARapid_x2_N1"
		define_var_if -Ee VM_NAME "$option_num = 8" "PAQoE_Controller_x2_N0"
		define_var_if -Ee VM_NAME "$option_num = 9" "PAQoE_Controller_x2_N1"
		define_var_if -Ee VM_NAME "$option_num = 10" "PARapid_N0"
		define_var_if -Ee VM_NAME "$option_num = 11" "PAQoE_Controller_N1"
		define_var_if -Ee VM_NAME "$option_num = 12" "PADirector"
		update_env_file VM_NAME
		echo_log_var -rj VM_NAME
		
		pre_vm $VM_NAME
		
		define_var_if_else -Ee vm_exists "`echo $VM_LIST | grep -c $VM_NAME` = 1" "1" "0"

		if [[ $vm_exists = 0 ]]; then
			display -Ef "sleep 5" "VM '$VM_NAME' is not on VM list '$VM_LIST'"
		else

			echo_log "Check oreder VM installation"

			define_var -Ee breakFlage "1"
			for vm in `echo $VM_LIST | sed 's/,/ /g'`; do
				[[ $vm = $VM_NAME ]] && break

				var -N vm_on_list "echo $VM_LIST_ON_HOST | grep -c $vm"
				if [[ $vm_on_list = 0 ]]; then

					display -Ef "sleep 5" "Before creating '$VM_NAME' you need to create '$vm' first"
					define_var -Ee breakFlage "0"
				fi
			done
			[[ $breakFlage = 1 ]] && break
		fi
		
	done
	
	delete_vm
	
	define_parameters

	before_start_vm_installation

	check_common_vars

	end_function
}

function delete_vm()
{
	para_fun_l $*; start_function delete_vm "Remove vm"

	var -N qcow2_exists "ls $VM_IMG_DIR | grep -c $VM_NAME.qcow2"
	check_var -Ee deploy_script

	if [[ $deploy_script = deploy-xml.sh ]]; then
		define_var -Ee mesg "Do you want to create new xml only"
		define_var -Ee destroy_undefine "virsh_stop"
	else
		define_var -Ee mesg "Do you want to reinstall it"
		define_var -Ee destroy_undefine "virsh_undefine"
	fi
	if [[ $qcow2_exists = 1 ]]; then
		whiptail --title "$VM_NAME" --defaultno --yesno "VM '$VM_NAME' is already exists\n$mesg?" 12 60
		define_var_if_else -Ee destroy_vm "$? -ne 0" "no" "yes"
		if [[ $destroy_vm = no ]]; then
			display -Ee "User asked not destroy VM '$VM_NAME'"
		else
			$destroy_undefine
		fi
	fi

	end_function
}	

function define_parameters()
{
	para_fun_l $*; start_function define_parameters "Define parmeters for VM"

	define_var -Ee ${PRE}VM_IMG_PATH "$VM_IMG_DIR/$VM_NAME.qcow2"
	update_env_file ${PRE}VM_IMG_PATH

	var -Ee iso_file "echo $VM_NAME_GROUP | awk -F'_' '{print \$1}' | tr 'A-Z' 'a-z'"
	define_var -Ee ISO_FILE "$VM_IMG_DIR/$iso_file.iso"
	update_env_file "${PRE_VM}ISO_FILE=$ISO_FILE"
	update_env_file ISO_FILE

	end_function
}
	
function before_start_vm_installation()
{
	para_fun_l $*; start_function before_start_vm_installation "Before start vm installation. VM=$VM_NAME"

	virsh_undefine

	replace_char_by_char_4_var_2_small -Ee VM_NAME_GROUP "," "space"
	for vm_name in $vm_name_group; do
		case $vm_name in
			UB)
				define_var_if_else -Ee VM_SIZE "$ONE_VM_INCLUDES = yes" "70000" "80000"
				define_var -Ee COREDUMPS_SIZE "220000"

				update_env_file COREDUMPS_SIZE
				echo_log_var -r ${PRE_VM}COREDUMPS_SIZE
			;;
			CELERITY|CELERITY_1|CELERITY_2|CELERITY_3)
				define_var_if_else -Ee VM_SIZE "$DMIDECODE_PLATFORM = OptiPlex" "87000" "180000"
				define_var_if -Ee VM_SIZE "$DMIDECODE_PLATFORM != OptiPlex && $ONE_VM_INCLUDES = yes" "170000"
			;;
			PAD)
				define_var -Ee VM_SIZE "75000"
			;;
			*)	display -Ee "Can not find variable 'VM_SIZE'"
			;;
		esac

		update_env_file "${PRE_VM}VM_SIZE=$VM_SIZE"
		update_env_file VM_SIZE
		echo_log_var -r ${PRE_VM}VM_SIZE
	done
	
	if [[ $UB_ONLY = yes ]]; then
		display -A  "COREDUMPS_SIZE will define letter"	
	else
		if [[ $VM_NAME_GROUP = UB ]]; then
			update_env_file COREDUMPS_SIZE

			update_env_file "${PRE_VM}COREDUMPS_SIZE=$COREDUMPS_SIZE"
			echo_log_var -r ${PRE_VM}COREDUMPS_SIZE
		fi
	fi

	end_function
}


# Function for ip managment guest  
############################################

function config_network_4_vm()
{
	para_fun_l $*; start_function config_network_4_vm "Define network for vm. VM=$VM_NAME"

	if [[ $IPV_MODE = 1 || $IPV_MODE = 3 ]]; then
		echo_log -l "[[ $IPV_MODE = 1 || $IPV_MODE = 3 ]]"

	    if [[ $VM_NAME_GROUP = UB ]]; then
	    	echo_log -l "VM_NAME_GROUP=$VM_NAME_GROUP"

	        # in this version the celerity IP address is configured internaly in the VM clonezilla installation, will be changed in the future
			set_address "GUEST IP ipv4"		IPADDR_GUEST
		else
			echo_log -l "VM_NAME_GROUP=$VM_NAME_GROUP"

			define_var -Ee IPADDR_GUEST "0.0.0.0"
		fi
		update_env_file "${PRE_VM}IPADDR_GUEST=$IPADDR_GUEST"
	fi
	if [[ $IPV_MODE = 2 || $IPV_MODE = 3 ]]; then
		echo_log -l "[[ $IPV_MODE = 2 || $IPV_MODE = 3 ]]"

		set_address "GUEST IP ipv6"		IPADDR_GUEST6
		
		update_env_file "${PRE_VM}IPADDR_GUEST6=$IPADDR_GUEST6"
	fi

	var -N IPADDR_GUEST "eval \"echo \$${PRE_VM}IPADDR_GUEST\""
	update_env_file "-n \"$IPADDR_GUEST\"" IPADDR_GUEST

	var -N IPADDR_GUEST6 "eval \" echo \$${PRE_VM}IPADDR_GUEST6\""
	update_env_file "-n \"$IPADDR_GUEST6\"" IPADDR_GUEST6

	define_var_if -Ee UB_IPADDR_GUEST "$VM_NAME_GROUP = UB && -n \"$IPADDR_GUEST\"" "$IPADDR_GUEST"
	update_env_file "$VM_NAME_GROUP = UB && -n \"$IPADDR_GUEST\"" UB_IPADDR_GUEST

	define_var_if -Ee UB_IPADDR_GUEST6 "$VM_NAME_GROUP = UB && -n \"$IPADDR_GUEST6\"" "XX$IPADDR_GUEST6"
	update_env_file "$VM_NAME_GROUP = UB && -n \"$IPADDR_GUEST6\"" UB_IPADDR_GUEST6

	end_function
}


# Function creating fsat-path.env and peerapp.env
############################################

function config_fast_path()
{
	para_fun_l $* ; start_function config_fast_path "Configure env files 'fast-path.env' and 'peerapp.env'. VM=$VM_NAME"

	if [[ $VM_NAME_GROUP != UB && $VM_NAME != PARapid_4 ]]; then
		display -A "Run on 'ub' installation only. VM_NAME_GROUP != UB && VM_NAME != PARapid_4"; end_function; return 
	fi

	var -Ee cores "echo $GUEST_ISOL_CORES_ID | tr ',' ' ' "
	var -Ee num_cores "echo $cores | awk '{print NF}'"
	
	var -Ee cores_list "echo $cores | rev | cut -d' ' -f $(($MUXERS+1))- | rev"
	var -Ee muxers_list "echo $cores | rev | cut -d' ' -f 1-$MUXERS | rev"
 
	var -Ee interfaces "echo $DATA_INTERFACES | tr ',' ' '"
	var -Ee num_interfaces "echo $interfaces | awk '{print NF}'"
	var -Ee interface_num "seq 0 $(($num_interfaces-1)) | tr '\n' ' '"

	define_var_if_else -Ee nb_mbuf "$num_cores -gt 5" "524688" "262144"      # 6.2 values dor increased ring
	
	reset_var -Ee list
	var -Ee last_num "echo $cores | awk '{print \$NF}'"
	for i in `seq 0 $last_num`; do
		define_var_if_else -N found "`echo $cores | grep -cw $i` = 0" "0" "1" 
		define_var -Ee list "$list$found"
	done
	var -Ee list "echo $list | rev"

	echo_log -l 'echo "obase=16;ibase=2; $list" | bc'
	cpu_mask=$(echo "obase=16;ibase=2; $list" | bc)
	show_var -Ee cpu_mask
	var -Ee cpu_mask "echo \"0x$cpu_mask\" | tr 'A-Z' 'a-z'"
	show_var -Ee cpu_mask

	for eth in $interfaces; do
		var -Ee mac_address "cat /sys/class/net/$eth/address"
		define_var -Ee whitelist "$whitelist -w $mac_address "
	done
	var -Ee whitelist "echo $whitelist | sed -e 's/ $//' -e 's/^ //'"
	show_var -Ee whitelist
	
	reset_var -Ee core_mapping
	for cpu in $cores_list; do
		define_var -Ee core_mapping "${core_mapping}c$cpu="
		for i in $interface_num; do
			define_var -Ee core_mapping "${core_mapping}$i:"
		done
		var -Ee core_mapping "echo $core_mapping | sed 's/:$/\//'"
	done
	
	var -Ee core_mapping_fastpath "echo $core_mapping | sed -e 's/\/$//' -e 's/^ //'"

	var -Ee muxer1 "echo $muxers_list | awk '{print \$1}'"
	var_if_else -Ee muxer2 "$MUXERS = 2 " "echo $muxers_list | awk '{print \$2}'" "echo $muxer1"
		
	define_var -Ee muxer "$muxer1"
	reset_var -Ee core_mapping
	for core in $cores_list; do
		for interface in $interface_num; do
			define_var -Ee core_mapping "$core_mapping$core=$interface=$muxer/"
			define_var_if_else -N muxer "$muxer = $muxer1" "$muxer2" "$muxer1"
		done
	done
	
	var -Ee core_mapping_peerapp "echo $core_mapping | sed 's/\/$//'"

	cat > $fast << EOF
### FastPath Configuration File ###
: \${NB_MEM_CHANNELS:=4}
: \${RESERVE_FP_HUGEPAGES:=off}
: \${HUGEPAGES_DIR:=/mnt/huge}
: \${VM_MEMORY:=auto}
: \${NB_MBUF:=$nb_mbuf}
# CPU Mask
: \${FP_MASK:=$cpu_mask}
# WhiteList
: \${FP_PORTS:=$whitelist}
#Core Port Mapping
: \${CORE_PORT_MAPPING:="$core_mapping_fastpath"}
: \${FPNSDK_OPTIONS:= --nb-rxd=4096 --nb-txd=2048}
### END OF FILE ###
EOF

	cat > $peerapp << EOF
### PeerApp Configuration file for FastPath ###
: \${FP_FILLER:= pang}
#Format: [[at_recvcore=]at_recvport=to_destcore/][at_recvcore=]at_recvport=to_destcore
: \${FP_MUXER_CPUPORTMAP="$core_mapping_peerapp"}
### END OF FILE ###
EOF

	show_file -Ees $fast
	show_file -Ees $peerapp

	end_function
}

# Function for creating VM disk  
############################################

function config_vm_system_disk()
{
	para_fun_l $*; start_function config_vm_system_disk "Create system image for vm. VM=$VM_NAME"

	check_var -Ee deploy_script
	if [[ $deploy_script = deploy-xml.sh ]]; then
		echo_log "Createing xml only"; end_function; return
	fi

    run_com_if -Ee "-f $VM_IMG_PATH" "rm -f $VM_IMG_PATH"

	run_com -Ee "qemu-img create -f qcow2 -o preallocation=falloc $VM_IMG_PATH ${VM_SIZE}M" 

	update_env_file "${PRE}VM_SIZE=$VM_SIZE"

	end_function
}

# Function for creating VM disk  
############################################

function config_vm_coredump_disk()
{
	para_fun_l $*; start_function config_vm_coredump_disk "Create coredump image for vm. VM=$VM_NAME"
	
	check_var -Ee deploy_script
	if [[ $deploy_script = deploy-xml.sh ]]; then
		echo_log "Createing xml only"; end_function; return
	fi

	if [[ $VM_NAME_GROUP != UB ]]; then
		display -A "Coredump disk for 'ub' only. VM_NAME_GROUP != UB"; end_function; return
	fi

	update_env_file "VM_COREDUMP_PATH=$VM_IMG_DIR/${VM_NAME}_coredumps.qcow2"
	update_env_file "${PRE_VM}VM_COREDUMP_PATH=$VM_COREDUMP_PATH"
	
	run_com_if -Ee "-f $VM_COREDUMP_PATH" "rm -f $VM_COREDUMP_PATH"	
    
    var -Ee opt_size "df -m /opt | grep -v Filesystem | awk '{print \$4}' | tr -d M"
    var -Ee coredumps_size "echo \"$(($opt_size / 100 * 95))\""
    	
    define_var -Ee COREDUMPS_SIZE $coredumps_size
    define_var_if -Ee COREDUMPS_SIZE "$COREDUMPS_SIZE -gt 400000" "400000"
    update_env_file COREDUMPS_SIZE

	update_env_file "${PRE_VM}COREDUMPS_SIZE=$COREDUMPS_SIZE"
	echo_log_var -r ${PRE_VM}COREDUMPS_SIZE

	run_com -Ee "qemu-img create -f qcow2 -o preallocation=falloc $VM_COREDUMP_PATH ${COREDUMPS_SIZE}M"

	end_function
}


# Function for handling memory 
############################################

function config_memory_vm()
{
	para_fun_l $*; start_function config_memory_vm "Config memory for vm. VM=$VM_NAME"

	reset_var -Ee NUMA_0_MEM
	reset_var -Ee NUMA_1_MEM
	
	define_var_if_else -Ee huge_pages_pad "$PAD_INCLUDES = yes" "4096" "0"
	var_if_else -Ee huge_pages_pad_half "$PAD_INCLUDES = yes" "echo \"$(($huge_pages_pad / 2))\"" "echo 0"

	if [[ $CELERITY_2_3_FLAG = 1 && $VM_NAME_GROUP != PAD ]]; then
		echo_log -l "config_memory_vm(): CELERITY_2_3_FLAG=$CELERITY_2_3_FLAG"

		var -Ee numa_huge_pages "eval \"echo \"\$HUGEPG$NUMA_ID\"\""
		var -Ee numa_huge_pages "echo \"$(($numa_huge_pages - $huge_pages_pad_half))\""
		define_var -Ee HUGE_PAGES_NUMA_$NUMA_ID "$numa_huge_pages"
		var -Ee NUMA_${NUMA_ID}_MEM "echo \"$(($numa_huge_pages * 2048))\""

	elif [[ $DMIDECODE_PLATFORM = OptiPlex ]]; then
		echo_log -l "config_memory_vm(): DMIDECODE_PLATFORM=$DMIDECODE_PLATFORM"

		define_var -Ee HUGE_PAGES_NUMA_0 "$HUGEPG0"
		var -Ee NUMA_0_MEM "echo \"$(($HUGEPG0 * 2048))\""

	elif [[ $ONE_NUMA_WITH_UB_AND_CELERITY = yes ]]; then
		echo_log -l "config_memory_vm(): ONE_NUMA_WITH_UB_AND_CELERITY=$ONE_NUMA_WITH_UB_AND_CELERITY"

		define_var_if_else -Ee ub_mem "$VM_NAME_GROUP = UB && $TOTAL_MEMORY -ge 62" "40" "20"
		define_var_if_else -Ee celerity_mem "$VM_NAME_GROUP != UB && $TOTAL_MEMORY -ge 62" "16" "8"
		define_var_if_else -Ee NUMA_0_MEM "$VM_NAME_GROUP = UB" "$ub_mem" "$celerity_mem"
		var -Ee NUMA_0_MEM "echo \"$(($NUMA_0_MEM * 1024 * 1024))\""
		var -Ee HUGE_PAGES_NUMA_0 "echo \"$(($NUMA_0_MEM / 2048))\""
	else
		echo_log -l "config_memory_vm(): All other cases"

		define_var -Ee HUGE_PAGES_NUMA_0 "$HUGEPG0"
		define_var_if -Ee HUGE_PAGES_NUMA_1 "$NUMA = yes" "$HUGEPG1"

		define_var_if_else -Ee numa_ids "$NUMA = yes" "0 1" "0"

		if [[ $VM_NAME_GROUP != PAD ]]; then
				echo_log "\n**** RUN ON VM '$VM_NAME'"
		
			if [[ $NUMA = yes ]]; then
				define_var_if -Ee huge_pages_pad "$PAD_INCLUDES = yes" "$huge_pages_pad_half"
				define_var_if_else -Ee numa_id_vm "$NUMA_ID = 1" "1" "0"
				define_var_if -Ee numa_ids "$UB_CELERITY_INCLUDES = yes" "$numa_id_vm"
			fi

			for numa_id in $numa_ids; do
				echo_log "\n**** RUN ON '$VM_NAME' NUMA id: '$numa_id'"
				
				var -Ee numa_huge_pages "echo HUGE_PAGES_NUMA_${numa_id}"
				define_var -Ee numa_mem "NUMA_${numa_id}_MEM"
				var -Ee $numa_huge_pages "echo \"$(($numa_huge_pages - $huge_pages_pad))\""
				var -Ee $numa_mem "echo \"$(($numa_huge_pages * 2048))\""
			done
		else
			echo_log "\n**** RUN ON VM 'PADirector'"

			if [[ $PAD_ONLY = yes ]]; then
					define_var -Ee huge_pages_pad "0"
			else
				define_var -Ee huge_pages_pad "$huge_pages_pad_half"
				define_var -Ee HUGE_PAGES_NUMA_0 "$huge_pages_pad"
				define_var -Ee HUGE_PAGES_NUMA_1 "$huge_pages_pad"
			fi
			for numa_id in $numa_ids; do
				echo_log "\n**** RUN ON '$VM_NAME' NUMA id: '$numa_id'"
			
				var -Ee numa_huge_pages "echo HUGE_PAGES_NUMA_${numa_id}"
				define_var -Ee numa_mem "NUMA_${numa_id}_MEM"
				var -Ee $numa_mem "echo \"$(($numa_huge_pages * 2048))\""	
			done
		fi
	fi

	#define_memory_vm
	update_env_file "-n \"$NUMA_0_MEM\"" "${PRE_VM}HUGE_PAGES_NUMA_0=$HUGE_PAGES_NUMA_0"
	update_env_file "-n \"$NUMA_0_MEM\"" HUGE_PAGES_NUMA_0
	echo_log_var -r "-n \"$NUMA_0_MEM\"" ${PRE_VM}HUGE_PAGES_NUMA_0

	update_env_file "-n \"$NUMA_0_MEM\"" "${PRE_VM}NUMA_0_MEM=$NUMA_0_MEM"
	update_env_file "-n \"$NUMA_0_MEM\"" NUMA_0_MEM
	echo_log_var -r "-n \"$NUMA_0_MEM\"" ${PRE_VM}NUMA_0_MEM

	define_var_if -Ee NUMA_0_MEM "-z \"$NUMA_0_MEM\"" "0"	

	update_env_file "-n \"$NUMA_1_MEM\"" "${PRE_VM}HUGE_PAGES_NUMA_1=$HUGE_PAGES_NUMA_1"
	update_env_file "-n \"$NUMA_1_MEM\"" HUGE_PAGES_NUMA_1
	echo_log_var -r "-n \"$NUMA_1_MEM\"" ${PRE_VM}HUGE_PAGES_NUMA_1

	update_env_file "-n \"$NUMA_1_MEM\"" "${PRE_VM}NUMA_1_MEM=$NUMA_1_MEM"
	update_env_file "-n \"$NUMA_1_MEM\"" NUMA_1_MEM
	echo_log_var -r "-n \"$NUMA_1_MEM\"" ${PRE_VM}NUMA_1_MEM

	define_var_if -Ee NUMA_1_MEM "-z \"$NUMA_1_MEM\"" "0"

	var -Ee MEMORY "echo \"$(($NUMA_0_MEM + $NUMA_1_MEM))\""
	update_env_file "${PRE_VM}MEMORY=$MEMORY"
	update_env_file MEMORY
	echo_log_var -r ${PRE_VM}MEMORY

	end_function
}

function define_memory_vm()
{
	para_fun_l $*; start_function define_memory_vm "Define memory for vm. VM=$VM_NAME"

	update_env_file "-n \"$NUMA_0_MEM\"" "${PRE_VM}HUGE_PAGES_NUMA_0=$HUGE_PAGES_NUMA_0"
	update_env_file "-n \"$NUMA_0_MEM\"" HUGE_PAGES_NUMA_0
	echo_log_var -r "-n \"$NUMA_0_MEM\"" ${PRE_VM}HUGE_PAGES_NUMA_0

	update_env_file "-n \"$NUMA_0_MEM\"" "${PRE_VM}NUMA_0_MEM=$NUMA_0_MEM"
	update_env_file "-n \"$NUMA_0_MEM\"" NUMA_0_MEM
	echo_log_var -r "-n \"$NUMA_0_MEM\"" ${PRE_VM}NUMA_0_MEM

	define_var_if -Ee NUMA_0_MEM "-z \"$NUMA_0_MEM\"" "0"	

	update_env_file "-n \"$NUMA_1_MEM\"" "${PRE_VM}HUGE_PAGES_NUMA_1=$HUGE_PAGES_NUMA_1"
	update_env_file "-n \"$NUMA_1_MEM\"" HUGE_PAGES_NUMA_1
	echo_log_var -r "-n \"$NUMA_1_MEM\"" ${PRE_VM}HUGE_PAGES_NUMA_1

	update_env_file "-n \"$NUMA_1_MEM\"" "${PRE_VM}NUMA_1_MEM=$NUMA_1_MEM"
	update_env_file "-n \"$NUMA_1_MEM\"" NUMA_1_MEM
	echo_log_var -r "-n \"$NUMA_1_MEM\"" ${PRE_VM}NUMA_1_MEM

	define_var_if -Ee NUMA_1_MEM "-z \"$NUMA_1_MEM\"" "0"

	var -Ee MEMORY "echo \"$(($NUMA_0_MEM + $NUMA_1_MEM))\""
	update_env_file "${PRE_VM}MEMORY=$MEMORY"
	update_env_file MEMORY
	echo_log_var -r ${PRE_VM}MEMORY

	end_function
}


# Function for convert xml to VM
############################################

function config_guest_cores()
{
	para_fun_l $*; start_function config_guest_cores "Create core list for vm. VM=$VM_NAME"

	if [[ $VM_NAME_GROUP = PAD ]]; then
		display -A "No NUMA_ID on 'PADirector' VM_NAME_GROUP=$VM_NAME_GROUP"
	fi

	check_var -Ee HOST_NUMA_0_CORES_AND_HYPER_CORES
	check_var_if -Ee HOST_NUMA_1_CORES_AND_HYPER_CORES "$NUMA = yes"
	run_com -Ee "virsh nodeinfo"

	var -Ee num_sockets "lscpu | grep Socket | awk '{print \$2}'"

	echo_log -l "Run case on VM_LIST_GROUP=$VM_LIST_GROUP"
	
	case $VM_LIST_GROUP in
		ub|celerity_1|pad)				cores_one_only ;;
		ub,celerity_1)					cores_ub_celerity ;;
		ub,pad|celerity_1,pad)			cores_ub_or_celerity_with_pad ;;
		ub,celerity_1,pad|\
		celerity_2,pad|celerity_3,pad)	cores_ub_celerity_pad ;;
		celerity_2|celerity_3)			cores_celerity_2 ;;
	esac

	update_env_file "${PRE_VM}GUEST_CORES=$GUEST_CORES"
	update_env_file GUEST_CORES
	echo_log_var -r ${PRE_VM}GUEST_CORES
	
	var -Ee NUMBER_GUEST_CORES "echo $GUEST_CORES | awk -F',' '{print NF}'"
	update_env_file "${PRE_VM}NUMBER_GUEST_CORES=$NUMBER_GUEST_CORES"
	update_env_file NUMBER_GUEST_CORES
	echo_log_var -r ${PRE_VM}NUMBER_GUEST_CORES
	
	var -Ee THREADS "virsh nodeinfo | grep 'Thread(s) per core:' | awk '{print \$NF}'"
	update_env_file "${PRE_VM}THREADS=$THREADS"
	update_env_file THREADS
	echo_log_var -r ${PRE_VM}THREADS
	
	define_var_if_else -Ee multi "$NUMA = yes && ($ONE_VM_WITHOUT_PAD_INCLUDES = yes || $VM_NAME = PADirector)" "4" "2"
	var -Ee CORES_PER_SOCKET "echo \"$NUMBER_GUEST_CORES / $multi\" | bc"
	update_env_file "${PRE_VM}CORES_PER_SOCKET=$CORES_PER_SOCKET"
	update_env_file CORES_PER_SOCKET
	echo_log_var -r ${PRE_VM}CORES_PER_SOCKET

	define_var_if_else -Ee SOCKETS "$NUMA = yes && ($ONE_VM_WITHOUT_PAD_INCLUDES = yes || $VM_NAME = PADirector)" "2" "1"
	update_env_file "${PRE_VM}SOCKETS=$SOCKETS"
	update_env_file "$VM_NAME_GROUP = UB" "UB_SOCKETS=$SOCKETS"
	update_env_file SOCKETS
	echo_log_var -r ${PRE_VM}SOCKETS

	pre_vm $VM_NAME

	end_function
}

function cores_one_only()
{
	para_fun_l $*; start_function cores_one_only "Create core list for one vm. VM=$VM_NAME"

	define_var -Ee GUEST_CORES "$HOST_CORES_AND_HYPER_CORES"
	
	end_function
}

function cores_ub_celerity()
{
	para_fun_l $*; start_function cores_ub_celerity "Create core list for one VM ub or celerity VM=$VM_NAME"
	
	var -Ee GUEST_CORES "eval \"echo \"\$HOST_NUMA_${NUMA_ID}_CORES_AND_HYPER_CORES\"\""

	end_function
}

function cores_ub_or_celerity_with_pad()
{
	para_fun_l $*; start_function cores_ub_or_celerity_with_pad "Create core list for one VM ub or celerity and pad. VM='$VM_NAME'"

	echo_log -l "cores_ub_or_celerity_with_pad(): VM_NAME_GROUP=$VM_NAME_GROUP"

	if [[ $VM_NAME_GROUP != PAD ]]; then
		define_var -Ee remove_2 "3-"
		define_var -Ee remove_4 "5-"

		var_if -Ee guest_cores_0 "$NUMA = yes" "echo $HOST_NUMA_0_CORES_AND_HYPER_CORES | cut -d ',' -f $remove_2"
		var_if -Ee guest_cores_1 "$NUMA = yes" "echo $HOST_NUMA_1_CORES_AND_HYPER_CORES | cut -d ',' -f $remove_2"
		var_if -Ee GUEST_CORES "$NUMA = yes" "echo \"$guest_cores_0,$guest_cores_1\" | sed -e 's/,,/,/g' -e 's/,\$//'"

		var_if -Ee GUEST_CORES "$NUMA = no" "echo $HOST_CORES_AND_HYPER_CORES | cut -d ',' -f $remove_4"
		
	else
		define_var -Ee get_2 "1-2"
		define_var -Ee get_4 "1-4"

		var_if -Ee guest_cores_0 "$NUMA = yes" "echo $HOST_NUMA_0_CORES_AND_HYPER_CORES | cut -d ',' -f $get_2"
		var_if -Ee guest_cores_1 "$NUMA = yes" "echo $HOST_NUMA_1_CORES_AND_HYPER_CORES | cut -d ',' -f $get_2"
		var_if -Ee GUEST_CORES "$NUMA = yes" "echo \"$guest_cores_0,$guest_cores_1\" | sed -e 's/,,/,/g' -e 's/,\$//'"

		var_if -Ee GUEST_CORES "$NUMA = no" "echo $HOST_CORES_AND_HYPER_CORES | cut -d ',' -f $get_4"
	fi
		
	end_function
}

function cores_ub_celerity_pad()
{
	para_fun_l $*; start_function cores_ub_celerity_pad "Create core list for one VM ub and celerity and pad. VM='$VM_NAME'"

	echo_log -l "\ncores_ub_celerity_pad(): VM_NAME_GROUP=$VM_NAME_GROUP"

	if [[ $VM_NAME_GROUP != PAD ]]; then
		define_var -Ee remove_2 "3-"

		var -Ee GUEST_CORES  "eval \"echo \$HOST_NUMA_${NUMA_ID}_CORES_AND_HYPER_CORES\" | cut -d ',' -f $remove_2"
	else
		define_var -Ee get_2 "1-2"

		var_if -Ee guest_cores_0 "$NUMA = yes" "echo $HOST_NUMA_0_CORES_AND_HYPER_CORES | cut -d ',' -f $get_2"
		var_if -Ee guest_cores_1 "$NUMA = yes" "echo $HOST_NUMA_1_CORES_AND_HYPER_CORES | cut -d ',' -f $get_2"
		var -Ee GUEST_CORES "echo \"$guest_cores_0,$guest_cores_1\" | sed -e 's/,,/,/g' -e 's/,\$//'"
	fi
		
	end_function
}

function cores_celerity_2()
{
	para_fun_l $*; start_function cores_celerity_2 "Create core list for one VM celerity_2. VM=$VM_NAME"

	var -Ee GUEST_CORES "eval \"echo \"\$HOST_NUMA_${NUMA_ID}_CORES_AND_HYPER_CORES\"\""

	end_function
}

# Function for showing xml file 
############################################

function show_xml_file()
{
	para_fun_l $*; start_function show_xml_file "Show xml file for vm. VM=$VM_NAME"
	
	run_com -Ee "virsh dumpxml $VM_NAME > $temp_xml_file"
	show_file -Ee $temp_xml_file

	end_function
}

function pre_vm_name()
{
	para_fun_l $*; start_function pre_vm_name "Pre vm name. VM=$VM_NAME"

	define_var -Ee VM_NAME "$1"

	var -Ee PRE_VM "echo ${VM_NAME}_ | tr 'a-z' 'A-Z'"

	end_function
}

function pre_vm()
{
	para_fun_l $*; start_function pre_vm "Pre vm"

	clean_variables
	export_env

	define_var -Ee VM_NAME "$1"
	update_env_file VM_NAME

	var -Ee PRE_VM "echo ${VM_NAME}_ | tr 'a-z' 'A-Z'"
	update_env_file PRE_VM

	reset_var -Ee VM_NAME_GROUP
	define_var_if -Ee VM_NAME_GROUP "$VM_NAME = PACache || $VM_NAME = PALive" "UB"
	define_var_if -Ee VM_NAME_GROUP "$VM_NAME = PADirector" "PAD"
	define_var_if -Ee VM_NAME_GROUP "$CELERITY_2_FLAG = 1 && $VM_NAME != PADirector" "CELERITY_2"
	define_var_if -Ee VM_NAME_GROUP "$CELERITY_3_FLAG = 1 && $VM_NAME != PADirector" "CELERITY_3"
	define_var_if -Ee VM_NAME_GROUP "-z \"$VM_NAME_GROUP\"" "CELERITY_1"
	update_env_file VM_NAME_GROUP

	define_var_if_else -Ee VM_NAME_GROUP_FAMILY "`echo $VM_NAME_GROUP | grep -c CELERITY` = 1" "CELERITY" "$VM_NAME_GROUP"
	update_env_file VM_NAME_GROUP_FAMILY

	define_var -Ee PRE_VM_GROUP "${VM_NAME_GROUP}_"
	update_env_file PRE_VM_GROUP

	define_var -Ee list_1 "VM_SIZE NUMA_ID HUGE_PAGES_NUMA_0 HUGE_PAGES_NUMA_1 NUMA_0_MEM NUMA_1_MEM MEMORY"
	define_var -Ee list_2 "ISO_FILE"
	var -Ee data_interfaces "eval \"echo \"\$${PRE_VM}DATA_INTERFACES\"\""
	define_var_if -Ee list_3 "-n \"$data_interfaces\"" "DATA_INTERFACES"
	var -Ee socket "eval \"echo \"\$${PRE_VM}SOCKETS\"\""
	define_var_if -Ee list_4 "-n \"$socket\"" "GUEST_CORES NUMBER_GUEST_CORES CORES_PER_SOCKET SOCKETS THREADS"
 
	for name in $list_1 $list_2 $list_3 $list_4; do
		reset_var -Ee $name
		var -Ee name_para "eval \"echo \"${PRE_VM}$name\"\""
		var -Ee value_para "eval \"echo \"\$$name_para\"\""
		update_env_file "-n \"$value_para\"" "$name=$value_para"
	done
	
	end_function
}

# Function for creating variables the xml  
############################################

function config_xml_skeleton()
{
	para_fun_l $*; start_function config_xml_skeleton "Create xml skeleton for vm. VM=$VM_NAME"

	define_var_if -Ee NUMA_ID "$VM_NAME_GROUP = PAD" "0"

	show_var -Ees DMIDECODE_PLATFORM
	
	if [[ `echo $DMIDECODE_PLATFORM | grep -c 78` = 1 ]]; then
		case $dell_platform in
			78122) platform='R620';;
			78123) platform='T620';;
			78121) platform='R710';;
			78125) platform='R710XD';;
			7812B) platform='R820';;
			78127) platform='R420';;
			78128) platform='R520';;
			78126) platform='R320';;
			7812A) platform='R420';;
			78129) platform='T320';;
			78134) platform='R630';;
			78135) platform='R730';;
			78126) platform='T630';;
			78149) platform='R730XD';;
			78163) platform='R530';;
			78162) platform='R430';;
		esac
	else
	    define_var -Ee platform "$DMIDECODE_PLATFORM"
	fi
	
	define_var -Ee PLATFORM "PowerEdge $platform"

	define_var -Ees VENDOR "PeerApp"
	 
	define_var -Ees MANUFACTURER "$machine_type"

	var -Ee VERSION "dmidecode -t 1 | awk -F':' '/Version:/ {print \$2}' | sed 's/ //g'"

	var -Ee SERIAL "dmidecode -t 1 | awk -F':' '/Serial Number:/ {print \$2}' | tr -d ' '"
	
	var -Ee MEMORY "eval \"echo \$${PRE_VM}MEMORY\""

	define_var -Ee NUM_CORES_XML "$NUMBER_GUEST_CORES"
	
	arrange_cpu
	CPUPINS=`echo -e $cpu_pinning`
	arrange_emulatorpin

	numa_cell_cpu

	echo_log "Create file '$temp_xml'"

	cat > $temp_xml << EOF
<domain type='kvm' id='3'>
  <name>UB_TEMPLATE</name>
  <uuid>7a9eedb8-069d-e4e6-ab59-9d7f19c139b0</uuid>
  <memory unit='KiB'>$MEMORY</memory>
  <currentMemory unit='KiB'>$MEMORY</currentMemory>
  <memoryBacking>
  <hugepages>                                                                                                                                                                                                                               
    <page size='2048' unit='KiB' nodeset='$NUMA_VM_GROUP'/>               
 </hugepages>                                                                                                                                                                                                                               
   </memoryBacking>
<vcpu placement='static'>$NUM_CORES_XML</vcpu>
  <cputune>
$CPUPINS
    <emulatorpin cpuset='$CORE_WITHOUT_ISOL'/>
  </cputune>
  <numatune>
    <memory mode='strict' nodeset='$NUMA_VM_GROUP'/>
    $MEMNODE0
    $MEMNODE1
  </numatune>
  <resource>
    <partition>/machine</partition>
  </resource>
    <sysinfo type='smbios'>
      <bios>
        <entry name='vendor'>$VENDOR</entry>
      </bios>
      <system>
        <entry name='manufacturer'>$MANUFACTURER</entry>
        <entry name='product'>$PLATFORM</entry>
        <entry name='version'>$VERSION</entry>
        <entry name='serial'>$SERIAL</entry>
        <entry name='family'>$VM_NAME</entry>
      </system>
    </sysinfo>
  <os>
    <type arch='x86_64' machine='pc_i440'>hvm</type>
    <boot dev='hd'/>
    <bootmenu enable='yes'/>
    <smbios mode='mode_h_s'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
 $CPU_MODEL_XML
 $CPU_MODEL_XML_CELERITY
 <topology sockets='$SOCKETS' cores='$CORES_PER_SOCKET' threads='$THREADS'/>
 <numa>
	$NUMA_CELL0
	$NUMA_CELL1
 </numa>
  </cpu>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>qemu_kvm</emulator>
    <controller type='usb' index='0'>
      <alias name='usb0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pci-root'>
      <alias name='pci.0'/>
    </controller>
    <controller type='ide' index='0'>
      <alias name='ide0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
    </controller>
    <serial type='pty'>
      <target port='1'/>
    </serial>
    <serial type='file'>
      <source path='/var/log/consoles/${VM_NAME}.log'/>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='1'/>
    </console>
    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0'/>
      <alias name='channel0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='spice' port='5900' autoport='yes' listen='127.0.0.1'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1'/>
      <alias name='video0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <watchdog model='i6300esb' action='reset'>
        <alias name='watchdog0'/>
    </watchdog>
    <memballoon model='none'>
      <alias name='balloon0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </memballoon>
  </devices>
</domain>
EOF

	replace_str_4_file -Ee $temp_xml pc_i440  pc-i440fx-rhel7.0.0
	replace_str_4_file -Ee $temp_xml mode_h_s sysinfo 
	replace_str_4_file -Ee $temp_xml qemu_kvm /usr/libexec/qemu-kvm

	show_file -Eel $temp_xml
	
	end_function
}

function arrange_cpu()
{
	para_fun_l $*; start_function arrange_cpu "Arrange for vcpu. VM=$VM_NAME"

	reset_var -Ee cpu_pinning
	define_var -Ee vcpu_num "0"

	replace_char_by_char_4_var_2_small -Ee GUEST_CORES "," "space"
	for pcpu_num in $guest_cores; do
		define_var -Ee cpu_pinning "$cpu_pinning\t<vcpupin vcpu='$vcpu_num' cpuset='$pcpu_num'/>\n"
		var -Ee vcpu_num "echo \"$(($vcpu_num + 1))\""
	done

	end_function
}

function arrange_emulatorpin()
{
	para_fun_l $*; start_function arrange_emulatorpin "Arrange for emulatorpin pcpu. VM=$VM_NAME"

	echo_log "\narrange_emulatorpin(): VM_NAME_GROUP=$VM_NAME_GROUP"

	if [[ $VM_NAME_GROUP = UB || $VM_NAME = PARapid_4 ]]; then
		reset_var -Ee CORE_WITHOUT_ISOL
		var -Ee isol_cpus "echo $HOST_ISOL_CORES_ID $HOST_ISOL_HYPER_CORES_ID | tr ',' ' '"

		replace_char_by_char_4_var_2_small -Ee GUEST_CORES "," "space"
		for isol_cpu in $isol_cpus; do
			var -Ee guest_cores "echo \" $guest_cores \" | sed \"s/ $isol_cpu / /\""
		done 

		var -Ee CORE_WITHOUT_ISOL "echo $guest_cores | tr -s ' ' | tr ' ' ','"
	else
		define_var -Ee CORE_WITHOUT_ISOL "$GUEST_CORES"
	fi
	end_function
}

function numa_cell_cpu()
{
	para_fun_l $*; start_function numa_cell_cpu "Define numa_cell and cpu on xml. VM=$VM_NAME"

	reset_var -Ee NUMA_CELL0
	reset_var -Ee NUMA_CELL1

	var -Ee last_core_number "echo \"$NUMBER_GUEST_CORES - 1\" | bc"
	var -Ee half_core_number "echo \"$NUMBER_GUEST_CORES / 2 - 1\" | bc"
	var -Ee half_core_number_1 "echo \"$NUMBER_GUEST_CORES / 2\" | bc"

	define_var -Ee numa0_start_cpu "0"
	define_var_if_else -Ee numa0_end_cpu "$NUMA = no || $ONE_VM_WITHOUT_PAD_INCLUDES = no" "$last_core_number" "$half_core_number"
	define_var_if -Ee numa0_end_cpu "$VM_NAME = PADirector" "$half_core_number"
	define_var_if_else -Ee numa1_start_cpu "$ONE_VM_WITHOUT_PAD_INCLUDES = yes || $VM_NAME = PADirector" "$half_core_number_1" "0"
	define_var -Ee numa1_end_cpu "$last_core_number"
	define_var -Ee NODESET_NUMA "0"

	echo_log -l "numa_cell_cpu(): NUMA=$NUMA"

	if [[ $NUMA = yes ]]; then
		define_var_if_else -Ee NUMBER_NUMA_FOR_VM "$ONE_VM_WITHOUT_PAD_INCLUDES = yes" "2" "1"
		
		define_var_if_else -Ee NUMA_HOST_0 "$NUMBER_NUMA_FOR_VM = 2" "0" "$NUMA_ID"
		
		define_var_if_else -Ee NUMA_VM_GROUP "$NUMBER_NUMA_FOR_VM = 2" "0-1" "0"
		define_var -Ee NUMA_VM_0 "$NUMBER_NUMA_FOR_VM = 2" "0"

		define_var_if_else -Ee numa_id "$NUMBER_NUMA_FOR_VM = 2" "0" "$NUMA_ID"
		var -Ee memory "eval \"echo \"\$NUMA_${numa_id}_MEM\"\""
					
		define_var -Ee NUMA_CELL0 "<cell id='0' cpus='$numa0_start_cpu-$numa0_end_cpu' memory='$memory' unit='KiB'/>"
		define_var_if -Ee NUMA_CELL1 "$NUMBER_NUMA_FOR_VM = 2" "<cell id='1' cpus='$numa1_start_cpu-$numa1_end_cpu' memory='$NUMA_1_MEM' unit='KiB'/>"

		define_var -Ee MEMNODE0 "<memnode cellid='0' mode='strict' nodeset='$NUMA_HOST_0'/>"
		define_var_if -Ee MEMNODE1 "$NUMBER_NUMA_FOR_VM = 2" "<memnode cellid='1' mode='strict' nodeset='1'/>"				
	else
		echo_log -l "numa_cell_cpu(): NUMA=$NUMA"

		define_var -Ee numa0_end_cpu "$last_core_number"
		define_var -Ee NUMA_CELL0 "<cell id='0' cpus='$numa0_start_cpu-$numa0_end_cpu' memory='$NUMA_0_MEM' unit='KiB'/>"
		define_var -Ee NUMA_ID "0"
		define_var -Ee NODESET "0"
		define_var -Ee NODESET_NUMA "0"
		define_var -Ee MEMNODE0 "<memnode cellid='0' mode='strict' nodeset='0'/>"
	fi

	reset_var -Ee CPU_MODEL_XML
	reset_var -Ee CPU_MODEL_XML_CELERITY

	define_var_if_else -Ee CPU_MODEL_XML "$VM_NAME_GROUP_FAMILY = CELERITY && `echo $CPU_MODEL | grep -c V` = 0" "<cpu mode='custom' match='exact'>" "<cpu mode='host-passthrough'>"
	define_var_if -Ee CPU_MODEL_XML_CELERITY "$VM_NAME_GROUP_FAMILY = CELERITY && `echo $CPU_MODEL | grep -c V` = 0" "<model fallback='allow'>core2duo</model>"	

	end_function
}
	
############################################

function config_virt_clone()
{
	para_fun_l $*; start_function config_virt_clone "Copy xml to vm name. VM=$VM_NAME"

	define_var -Ee tmp_VM_NAME "/tmp/$VM_NAME.xml"

	run_com -Ee "virt-clone --original-xml=$temp_xml -n $VM_NAME"
	
	run_com -Ee "virsh dumpxml $VM_NAME > $tmp_VM_NAME"
	show_file -Eel $tmp_VM_NAME

	end_function
}

	
############################################

function config_virt_clone()
{
	para_fun_l $*; start_function config_virt_clone "Copy xml to vm. VM=$VM_NAME"

	define_var -Ee tmp_VM_NAME "/tmp/$VM_NAME.xml"

	run_com -Ee "virt-clone --original-xml=$temp_xml -n $VM_NAME"
	
	run_com -Ee "virsh dumpxml $VM_NAME > $tmp_VM_NAME"
	show_file -Eel $tmp_VM_NAME

	end_function
}

# Function for creating disk system to VM 
############################################

function config_local_disk()
{
	para_fun_l $*; start_function config_local_disk "Attach system disk to vm. VM=$VM_NAME"

	define_var -Ee VM_IMG_PATH "$VM_IMG_DIR/$VM_NAME.qcow2"

    define_var -Ee BDCACHE  "none"
    define_var_if_else -Ee BDIO "$VM_NAME_GROUP_FAMILY = CELERITY" "native" "threads"
	define_var_if_else -Ee BUS "$VM_NAME_GROUP = UB" "scsi" "sata"

	cat  > $temp_xml << EOF
    <disk type='file' device='disk'>
    	<driver name='qemu' type='qcow2' cache='$BDCACHE' io='$BDIO'/>
    	<source file='$VM_IMG_PATH'/>
    	<backingStore/>
    	<target dev='sda' bus='$BUS'/>
    	<address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
EOF

	virsh_attach 'system disk'

	end_function
}

function virsh_attach()
{
	para_fun_l $*; start_function virsh_attach "Attached $*"
	
	show_file -Ee $temp_xml "xml file"
	
	run_com -Ee "virsh attach-device --config $VM_NAME $temp_xml"
	
	end_function
}

# Function for creating core dumps
############################################

function config_coredumps_disk()
{
	para_fun_l $*; start_function config_coredumps_disk "Attache coredumps disk to vm. VM=$VM_NAME"

	if [[ $VM_NAME_GROUP != UB ]]; then
		display -A "Coredump disk for 'ub' only. VM_NAME_GROUP != UB"; end_function; return
	fi
	
	cat  > $temp_xml << EOF
    <disk type='file' device='disk'>
    	<driver name='qemu' type='qcow2' cache='none' io='threads'/>
    	<source file='$VM_IMG_DIR/${VM_NAME}_coredumps.qcow2'/>
    	<backingStore/>
    	<target dev='sdb' bus='scsi'/>
    	<address type='drive' controller='0' bus='0' target='1' unit='1'/>
    </disk>
EOF

	virsh_attach 'cordump disk'
	end_function
}

# Function for connecting cdrom 
############################################

function config_local_cdrom()
{
	para_fun_l $*; start_function config_local_cdrom "Attach local cdrom to vm. VM=$VM_NAME"

	iso="<source file=\"$ISO_FILE\"/>"
	cat > $temp_xml << EOF
	<disk type='file' device='cdrom'>
		<driver name='qemu' type='raw'/>
		$iso    
		<target dev='hda' bus='ide' tray='closed'/>
		<readonly/>
		<address type='drive' controller='0' bus='1' target='0' unit='0'/>
	</disk> 
EOF
	virsh_attach 'cdrom'

	end_function
}

# Function for adding network 
############################################

function config_guest_mgmt()
{
	para_fun_l $*; start_function config_guest_mgmt "Attach eth0 to vm. VM=$VM_NAME"

    # Turn into eth0 in guest 10.11.12.x
	cat  > $temp_xml << EOF 
	<interface type='direct'>
		<source dev='bond0' mode='vepa'/>
		<target dev='macvtap0'/>
		<model type='virtio'/>
		<alias name='net0'/>
    </interface>
EOF
	virsh_attach 'nic mgmt'

	end_function
}

# Function for adding isolated network
############################################

function config_isolated_network() 
{
	para_fun_l $*; start_function config_isolated_network "Create isolated network. VM=$VM_NAME"
	
	cat  > $temp_xml << EOF 
     <interface type='network'>
    	<source network='isolated'/>
    	<model type='virtio'/>
    </interface>
EOF
	virsh_attach 'isolated net'    

    cat  > $temp_xml << EOF 
	<network>
		<name>isolated</name>
		<ip address='10.11.13.254' netmask='255.255.255.0'>
		</ip>
	</network>
EOF
	show_file -Ee $temp_xml

	define_var_if_else -Ee isolated_net_exists "`virsh net-list --all | grep -c isolated` = 0" "not_exists" "exists"
    run_com_if -Ee "$isolated_net_exists = not_exists" "virsh net-define $temp_xml"
    run_com -Ee "virsh net-autostart isolated"
    define_var_if_else -Ee isolated_net_status "`virsh net-list --all | grep -c isolated` = 0 || `virsh net-list --all | grep isolated | grep -c inactive` = 1" "not_running" "running"
    run_com_if -Ee "$isolated_net_status = not_running" "virsh net-start isolated"

	end_function
}

# Function for adding nics to VM
############################################

function config_local_nics()
{
	para_fun_l $*; start_function config_local_nics "Attach nics to vm. VM=$VM_NAME"
	
	if [[ $VM_NAME_GROUP = PAD ]]; then
		display -A "Will not run on 'pad'"; end_function; return
	fi
	
	var -Ee nic_list "ls $DIR_NIC | egrep '^eno|^em|^ens|^enp|^p' | sort -V"
	
	if [[ X`ls $DIR_NIC | grep bond` = X ]]; then
		var -Ee nic_list "echo $nic_list | sed \"s/$MGMT_GUEST//\""
		case $MGMT_GUEST in
			eno1) define_var n "eno2";;
			eno2) define_var n "eno1";;
			eno3) define_var n "eno4";;
			eno4) define_var n "eno3";;
		esac
		var -Ee nic_list "echo $nic_list | sed \"s/$n//\""
	fi
	define_var -Ee count "1"
	for nic in $nic_list ; do
		if [[ `grep -c bond0 $nic_dir/ifcfg-$nic 2>/dev/null` != 1 ]]; then
			define_var_if_else -Ee mode "`echo $DATA_INTERFACES | grep -wc $nic` -eq 1" "passthrough" "macvtap"
			if [[ $mode = macvtap ]]; then
				[[ $count -gt 2 ]] && continue
				var -Ee count "echo \"$((++count))\""
			fi
			run_com -Ee "create_temp_nic_xml $nic $mode"
		fi
	done

	end_function
}

function create_temp_nic_xml()
{
	para_fun_l $*; start_function create_temp_nic_xml "Attach nics to VM VM=$VM_NAME"
	
	define_var -Ees nic "$1"
	define_var -Ees type "$2"

	run_com_if -Ee "$type != socket" "cd $DIR_NIC/$nic"
	var_if -Ee F "$type != socket" "readlink device"
	var_if -Ee G "$type != socket" "basename $F"
	var_if -Ee BUS "$type != socket" "echo $G | awk -F: '{print \$2}'"
	var_if -Ee SLOT "$type != socket" "echo $G | awk -F: '{print \$3}' | awk -F. '{print \$1}'"
	var_if -Ee FUNCTION "$type != socket" "echo $G | awk -F. '{print \$2}'"

	echo_log "Run on case type=$type"
	case $type in
		passthrough)
			cat > $temp_xml << EOF
	<hostdev mode='subsystem' type='pci' managed='yes'>
	<source>
        	 <address domain='0x0000' bus='0x$BUS' slot='0x$SLOT' function='0x$FUNCTION'/>
	</source>
	</hostdev>
EOF
			;;
			
		macvtap)	
			if [ `lspci | grep $BUS:$SLOT.$FUNCTION | grep -c Virtual` -eq 0 ]; then
				cat > $temp_xml << EOF
   <interface type='direct'>
		<source dev='$nic' mode='vepa'/>
		<model type='virtio'/>
   </interface>
EOF
			fi
			;;
		
		socket)
				num=`echo $nic | sed 's/eth//'`
				cat > $temp_xml << EOF
	<interface type='vhostuser'>
		<source type='unix' path='/tmp/vhost_socket$num' mode='client'/>
		<model type='virtio'/>
		<driver queues='4'/>
	</interface>
EOF
			;;
	esac

	virsh_attach $type $nic

	end_function
}

# Function for creating media cache_wed
############################################

function config_list_data_webcache_disk()
{
	para_fun_l $*; start_function config_list_data_webcache_disk "Create data and cache_web list. VM=$VM_NAME"

	if [[ $VM_NAME != PACache ]]; then
		display -A "Run on 'PACache' installation only. VM_NAME != PACache"; end_function; return
	fi

	rescan_controller
	get_disks_list
	remove_system_disk_from_list
	prepare_data_disk_list
	check_data_disks_same_size
	prepare_webcache_disk_list
	prepare_JBOD_disk_list
	reset_JBOD_disk
	
	end_function
}

# Function for creating media and webcache
############################################

function config_data_webcache_disk()
{
	para_fun_l $*; start_function config_data_webcache_disk "Create media cache_web list. VM=$VM_NAME"

	if [[ $VM_NAME != PACache ]]; then
		display -A "Run on 'PACache' installation only. VM_NAME != PACache "; end_function; return
	fi

	define_data_webcache_disk data     $DATA_DISKS_SLOT_LIST
	define_data_webcache_disk webcache $WEBCACHE_DISKS_SLOT_LIST
	
	end_function
}

# Function for defining data disks
############################################

function define_data_webcache_disk()
{
	para_fun_l $*; start_function define_data_webcache_disk "Define '$1' disk on controller"
	
	define_var -Ee disk_type $1
	define_var -N list_disk  $2
	replace_char_by_char_4_var -Ee list_disk "," "space"

	if [[ $list_disk = NO-DISKS ]]; then
		display -A "No Disks '$disk_type' exist on machine"; end_function; return
	fi 
			 
	for num_slot in $list_disk; do
		if [[ $disk_type = system ]]; then
			define_var_if_else -Ee disk_already_exists "`${MEGACLI} -LdPdInfo a0 | grep -c \"Slot Number: $num_slot\$\"` = 1" "1" "0"
		else
			define_var_if_else -Ee disk_already_exists "`${HPSSACLI} controller slot=0 show config | grep -B3 \" physicaldrive ${PORT_BOX}:$num_slot \" | grep -c logicaldrive` = 1" "1" "0"
		fi

		if [[ $disk_already_exists = 1 ]]; then
			echo_log "Disk on slot number '$num_slot' is already exists"
		else
			prepare_disk $disk_type $num_slot
		fi 
	done
	
	end_function
}

# Function for creating local disks data
############################################

function config_local_storage_data()
{
    para_fun_l $*; start_function config_local_storage_data "Attach data disks to vm. VM=$VM_NAME"
	    
    if [[ $VM_NAME != PACache ]]; then 
		display -A "Run on 'PACache' installation only. VM_NAME != PACache"; end_function; return
	fi

    if [[ $DATA_DISKS_SLOT_LIST = NO-DISKS ]]; then 
		display -Wf "No webcache disk on machine"; end_function; return
	fi
	
	check_var -Ee VIRTUAL_DATA_DISKS_LIST
	
	if [[ $DATA_DISKS_SLOT_LIST = NO-DISKS ]]; then
		echo_log -Wf "No DATA disks on HOST"; end_function; return
	fi
		
	define_var -Ee controller "0"
    define_var -Ee target "1"
    define_var -Ee scsi_drive "sdc"
	
	define_var_if_else -Ee drive_cFlag "`virsh dumpxml $VM_NAME | grep -c \"dev='sdc\"` = 1" "1" "0"
		
	if [[ $drive_cFlag = 1 ]]; then
		
		echo_log -s "Adding disk to machime"
		
		var -Ee scsi_drive "virsh dumpxml $VM_NAME | grep \"dev='sd\" | tail -1 | awk  -F \"'\" '{print \$2}'"
		var -Ee scsi_drive 'echo "\$x=$scsi_drive;\$x++; print \$x,\"\n\"" | perl'
		var -Ee target "virsh dumpxml $VM_NAME | egrep  \"controller='0'|bus='0'\" | grep \"type='drive'\" | tail -1 |  awk  -F \"'\" '{print \$8}'"
		var -Ee target "echo \"$((target + 1))\""
	fi

	replace_char_by_char_4_var -Ee VIRTUAL_DATA_DISKS_LIST "," "space"
	for data_disk in $VIRTUAL_DATA_DISKS_LIST; do

        if [ $target -eq 6 ]; then 
        	var -Ee controller "echo \"$((controller + 1))\""
			define_var -Ee target "0"
		else 
        	var -Ee target "echo \"$((target + 1))\""
        fi
  
        prepare_disk_4_vm_storage data $data_disk

        cat > $temp_xml << EOF
        <disk type='block' device='lun' rawio='yes' sgio='unfiltered'>
        <driver name='qemu' type='raw' cache='none' io='native'/>
        <source dev='$dev_wwn' startupPolicy='optional'/>
        <backingStore/>
        <target dev='$scsi_drive' bus='scsi'/>
        <address type='drive' controller='$controller' bus='0' target='$target' unit='$target'/>
        </disk>
EOF
		show_file -Ee $temp_xml
        var -Ee scsi_drive 'echo "\$x=$scsi_drive;\$x++; print \$x,\"\n\"" | perl'
        [[ $disk_found_in_xml = 0 ]] && virsh_attach "disk '$data_disk' '$size' as DATA disk with WWN '$WWN'"       
	done 

	run_com -Ee "virsh dumpxml $VM_NAME > $temp_xml_file"
	run_com -Ee "sed -i \"/<controller type='scsi' index=/a    <driver queues='4'/>\" $temp_xml_file"

	run_com -Ee "virsh define $temp_xml_file"
    end_function
}


# Function for partition ssd system disk
############################################

function config_ssd_partition_for_vd()
{
	para_fun_l $*; start_function config_ssd_partition_for_vd "Create vd disk on one of the partiton on system disk. VM=$VM_NAME"

	if [[ $VM_NAME_GROUP != UB ]]; then
		display -A "Run on 'PACache|PALive' installation only. VM_NAME_GROUP != UB"; end_function; return
	fi

	define_var -Ee VD_WEBCACHE "no"
	update_env_file VD_WEBCACHE
	
	if [[ $SYSTEM_DISK_TYPE != SSD ]]; then
		display -A "System disk is not SSD type, no webcache to create."; end_function; return
	fi
	
	var -Ee num_webcache "echo $WEBCACHE_DISKS_SLOT_LIST | awk -F ',' '{print NF}'"

	if [[ $num_webcache = 2 ]]; then
		display -A "Two disk webcache are already exist; no webcache to create on system disk"; end_function; return
	fi

	define_var -Ee UB_VM_SSD "vd_ub_SSD.qcow2"
	define_var -Ee UB_VM_SSD_PATH "$VM_IMG_DIR/$UB_VM_SSD"
	define_var -Ee UB_VD_QCOW2_SIZE "200000"
	define_var -Ee all_vm_size "400000"
	
	var -Ee opt_size_free "df -m | grep /opt | awk '{print \$4}'"
	var -Ee free_space "echo \"$(($opt_size_free - $all_vm_size))\""
	define_var_if_else -Ee space "$free_space -gt $UB_VD_QCOW2_SIZE" "big" "small" 

	if [[ $space = big ]]; then
		echo_log -l "webcache on system disk will be created"
		define_var -Ee VD_WEBCACHE "yes"
	
		run_com_if -Ee "-f $UB_VM_SSD_PATH" "rm -f $UB_VM_SSD_PATH"

		run_com -Ee "qemu-img create -f qcow2 -o preallocation=falloc $UB_VM_SSD_PATH ${UB_VD_QCOW2_SIZE}M" 

		update_env_file VD_WEBCACHE
		update_env_file UB_VM_SSD
		update_env_file UB_VM_SSD_PATH	
		update_env_file UB_VD_QCOW2_SIZE
	else
		display -A "Not enough space to create webcache on SSD system" 			
	fi
	
	end_function
}

# Function for creating local webcache disks
############################################

function config_local_storage_webcache()
{
	para_fun_l $*; start_function config_local_storage_webcache "Attach webcache disks to vm. $VM_NAME"

	if [[ $VM_NAME != PACache ]]; then
		display -A "Run on 'PACache' installation only. VM_NAME != PACache"; end_function; return
	fi
			
	if [[ $VD_WEBCACHE = no && $VIRTUAL_WEBCACHE_DISKS_LIST = NO-DISKS ]]; then
		echo_log_var -r VIRTUAL_WEBCACHE_DISKS_LIST
		display -A "No webcache disk on machine"; end_function; return
	elif [[ $VD_WEBCACHE = yes && $VIRTUAL_WEBCACHE_DISKS_LIST = NO-DISKS ]]; then
		define_var -Ee VIRTUAL_WEBCACHE_DISKS_LIST "$UB_VM_SSD"
	elif [[ $VD_WEBCACHE = yes && $VIRTUAL_WEBCACHE_DISKS_LIST != NO-DISKS ]]; then
		var -Ee VIRTUAL_WEBCACHE_DISKS_LIST "echo $VIRTUAL_WEBCACHE_DISKS_LIST | sed \"s/$UB_VM_SSD,//\""
		define_var -Ee VIRTUAL_WEBCACHE_DISKS_LIST "$VIRTUAL_WEBCACHE_DISKS_LIST,$UB_VM_SSD"
	fi
	update_env_file VIRTUAL_WEBCACHE_DISKS_LIST
	echo_log_var -r VIRTUAL_WEBCACHE_DISKS_LIST

	define_var -Ee vd_drive "vda"

	replace_char_by_char_4_var -Ee VIRTUAL_WEBCACHE_DISKS_LIST "," "space"
	for webcache_device in $VIRTUAL_WEBCACHE_DISKS_LIST; do
		prepare_disk_4_vm_storage webcache $webcache_device
		
		cat > $temp_xml << EOF
        <disk type='$block' device='disk'>
                <driver name='qemu' type='$type' cache='none' io='threads'/>
            	<source $dev='$dev_wwn' startupPolicy='optional'/>
                <backingStore/>
                <target dev='$vd_drive' bus='virtio'/>
        </disk>
EOF
		show_file -Ee $temp_xml
		var -Ee vd_drive 'echo "\$x=$vd_drive;\$x++; print \$x,\"\n\"" | perl'
		[[ $disk_found_in_xml = 0 ]] && virsh_attach "disk '$webcache_device' '$size' as WEBCACHE disk with WWN '$dev'"		
    done

	end_function
}

# Function for prepareing list
############################################

function config_prepare_data_disks_list()
{
	para_fun_l $*; start_function config_prepare_data_disks_list "Prepare disk list for data. VM=$VM_NAME"
	
	if [[ $VM_NAME != PACache ]]; then
		display -A "Run on 'PACache' installation only. VM_NAME != PACache"; end_function; return
	fi

	if [[ $DATA_DISKS_SLOT_LIST = NO-DISKS ]]; then
		echo_log -W "No DATA disks on HOST"
		define_var -Ee VIRTUAL_DATA_DISKS_LIST "NO-DISKS"
	else
		reset_var -Ee VIRTUAL_DATA_DISKS_LIST

		replace_char_by_char_4_var -Ee DATA_DISKS_SLOT_LIST "," "space"
		for slot in $DATA_DISKS_SLOT_LIST; do
			translate_physical_virtual_disk $slot
			define_var -Ee VIRTUAL_DATA_DISKS_LIST "$VIRTUAL_DATA_DISKS_LIST,/dev/$disk"
		done
	fi

	remove_first_last_char_4_var -Ee VIRTUAL_DATA_DISKS_LIST ","
	update_env_file VIRTUAL_DATA_DISKS_LIST
	echo_log_var -r VIRTUAL_DATA_DISKS_LIST

	end_function
}

# Function for prepareing list
############################################

function config_prepare_webcache_disks_list()
{
	para_fun_l $*; start_function config_prepare_webcache_disks_list "Prepare disk list for webcache. VM=$VM_NAME"

	if [[ $VM_NAME != PACache ]]; then
		display -A "Run on 'PACache' installation only"
		update_env_file WEBCACHE_DISKS_SLOT_LIST=NO-DISKS
		echo_log_var -r WEBCACHE_DISKS_SLOT_LIST
		end_function; return
	fi

	if [[ $WEBCACHE_DISKS_SLOT_LIST = NO-DISKS ]]; then
		display -A "No DATA disks on HOST"
		define_var -Ee VIRTUAL_WEBCACHE_DISKS_LIST "NO-DISKS"
	else
		reset_var -Ee VIRTUAL_WEBCACHE_DISKS_LIST
	
		replace_char_by_char_4_var -Ee WEBCACHE_DISKS_SLOT_LIST "," "space"
		for slot in $WEBCACHE_DISKS_SLOT_LIST; do
			translate_physical_virtual_disk $slot
			define_var -Ee VIRTUAL_WEBCACHE_DISKS_LIST "$VIRTUAL_WEBCACHE_DISKS_LIST,/dev/$disk"
		done
	fi

	remove_first_last_char_4_var -Ee VIRTUAL_WEBCACHE_DISKS_LIST ","
	update_env_file VIRTUAL_WEBCACHE_DISKS_LIST
	echo_log_var -r VIRTUAL_WEBCACHE_DISKS_LIST

	end_function
}

# Function for prepareing list
############################################

function prepare_disk_4_vm_storage()
{
	para_fun_l $*; start_function prepare_disk_4_vm_storage "Prepare disk for vm storage. VM=$VM_NAME"

	define_var -Ee vm_disk_type "$1"
	define_var -Ee vm_disk "$2"

	define_var -Ee vd_webcacheFlag "0" 
	
	if [[ $vm_disk_type = webcache ]]; then
		check_var -Ee VD_WEBCACHE
		define_var_if -Ee vd_webcacheFlag "$VD_WEBCACHE = yes" "1"
	fi
	
	if [[ $vd_webcacheFlag = 1 ]]; then
		check_var -Ee UB_VM_SSD_PATH
		define_var -Ee dev_wwn "$UB_VM_SSD_PATH"
	else
		var -Ee sd "echo $vm_disk | cut -d/ -f 3"
		var -Ee size "parted -s $vm_disk print 2>/dev/null | grep 'Disk /dev' | awk '/GB/ {split(\$3,a,\"G\"); print a[1];}'"
		var -Ee disk_line "ls /dev/disk/by-id/ -la | grep -w $sd"
		var -Ee WWN "ls /dev/disk/by-id/ -la | grep -w $sd | grep -w wwn | awk '{print \$9}'"
		define_var -Ee dev_wwn "/dev/disk/by-id/$WWN"
	fi

	var -N disk_found_in_xml "virsh dumpxml $VM_NAME | grep -c $dev_wwn"
		
	if [[ $disk_found_in_xml != 0 ]]; then
		echo_log "Disk '$vm_disk' '$size' '$dev' is already in $VM_NAME.xml file"
	fi

	define_var_if_else -Ee block	"$vd_webcacheFlag = 0" "block" "file"
	define_var_if_else -Ee type 	"$vd_webcacheFlag = 0" "raw"   "qcow2"
	define_var_if_else -Ee dev		"$vd_webcacheFlag = 0" "dev"   "file"

	end_function
}


# Function Translating physical virtual disk
############################################

function translate_physical_virtual_disk()
{
	para_fun_l $*; start_function translate_physical_virtual_disk "Translating physical virtual disk. VM=$VM_NAME"

	define_var -Ee slot "$1"

	show_var -Ees machine_type
	
	if [[ $machine_type_group = dell ]]; then
		var -Ee raid_controller_id "lspci -v | grep 'RAID bus controller: LSI Logic'|awk '{print \$1}'"
		var -Ee logicaldrive "${MEGACLI} -LdPdInfo a0 | egrep 'Virtual|Slot' | tr '\n' ' '| sed 's/Virtual/\nVirtual/g' | grep \"Number: $slot \" | awk '{print \$3}'"
		var -Ee disk "ls -la /dev/disk/by-path/ | grep -P \"pci-0000:${raid_controller_id}-scsi-.:.:${logicaldrive}:0\" | grep -v part|cut -d/ -f 3"
	else
		var -Ee logicaldrive "${HPSSACLI} controller slot=0 show config | grep -B2 \"$PORT_BOX:$slot\" | head -1 | awk '{print \$2}' | tr -d ' '"
		var -Ee disk "${HPSSACLI} ctrl slot=0 ld $logicaldrive show | grep 'Disk Name:' | awk -F':' '{print \$2}' | tr -d ' ' | sed 's!/dev/!!'"
	fi

	echo_log "physical '$slot' ; virtual '$logicaldrive' ; disk '$disk'"
	
	end_function
}


# Function for getting cores for guest
############################################

function config_guest_isol_cores()
{
	para_fun_l $*; start_function config_guest_isol_cores "Create isolated cores list for vm. VM=$VM_NAME"

	if [[ ! ( $VM_NAME_GROUP = UB || $VM_NAME = PARapid_4 ) ]]; then
		display -A "Run installation on 'ub' group only. ! ( VM_NAME_GROUP = ub || VM_NAME = PARapid_4 )"; end_function; return
	fi

	run_com -Ee "virsh dumpxml $VM_NAME | grep \"vcpupin vcpu=\" > $temp"
	show_file -Ee $temp
	display_if_not -Ee "-s $temp" "No cores found in '$VM_NAME' VM"

	get_guest_isol_cores GUEST_ISOL_CORES_ID "$HOST_ISOL_CORES_ID"
	get_guest_isol_cores GUEST_ISOL_HYPER_CORES_ID "$HOST_ISOL_HYPER_CORES_ID"

	update_env_file "${PRE_VM}GUEST_ISOL_CORES_ID=$GUEST_ISOL_CORES_ID"
	update_env_file GUEST_ISOL_CORES_ID
	
	update_env_file "${PRE_VM}GUEST_ISOL_HYPER_CORES_ID=$GUEST_ISOL_HYPER_CORES_ID"
	update_env_file GUEST_ISOL_HYPER_CORES_ID
		
	end_function
}

function get_guest_isol_cores()
{
	para_fun_l $*; start_function get_guest_isol_cores "Create isolated cores list for vm. VM=$VM_NAME"

	define_var -Ee isol_type "$1"
	define_var -Ee isol_list "$2"
	
	reset_var -Ee isol_guest_list

	replace_char_by_char_4_var -Ee isol_list "," "space"
	for isol in $isol_list; do
		var -Ee guest_isol "grep \"cpuset='$isol'\" $temp | awk -F\"'\" '{print \$2}'"
		define_var -Ee isol_guest_list "$isol_guest_list $guest_isol"
	done
	var -Ee isol_guest_list "echo $isol_guest_list| sed 's/ /,/g'"
	define_var -Ee $isol_type "$isol_guest_list"
	
	end_function
}


# Function to sort the mac addresses in ascending order for debian ascending interface order
############################################

function config_celerity_mac_reorder()
{
	para_fun_l $*; start_function config_celerity_mac_reorder "Sort Debian NICs in ascending order. VM=$VM_NAME"

    if [[ $VM_NAME_GROUP_FAMILY != CELERITY ]]; then
		display -A "Run on 'celerity' installation only. VM_NAME_GROUP_FAMILY != CELERITY"; end_function; return
	fi

	run_com -Ee "virsh dumpxml $VM_NAME > $temp_xml_file"
	run_com -Ee "grep -n '52:54' $temp_xml_file | sed 's!:!|!' | sed 's!\$!|!' > $temp1"
	run_com -Ee "grep '52:54' $temp_xml_file | sort -n > $temp2"
	run_com -Ee "paste $temp1 $temp2 > $temp"
	show_file -Eel $temp

	while read line; do
		echo_log -Eel "\nLine nic: $line\n"

		var -Ee str_old "echo \"$line\" | awk -F'|' '{print \$2}'"
		var -Ee str_new "echo \"$line\" | awk -F'|' '{print \$3}'"
		if [[ "$str_old" = "$str_new" ]]; then
			echo_log "Same strings"
			next
		else
			var -Ee num_line "echo \"$line\" | awk -F'|' '{print \$1}'"
			replace_by_line_number_4_file -Ee $temp_xml_file $num_line "$str_old" "$str_new"
		fi
	done < $temp

	show_command_output -Ee "grep '52:54' $temp_xml_file"
		
	run_com -Ee "virsh define $temp_xml_file"
		
	end_function
}

# Function Installing OS on VM
############################################

function install_vm()
{

	para_fun_l $*; start_function install_vm "Install operting system and more. VM=$VM_NAME"
	
	expect_file=/tmp/expect
		
cat > $expect_file << 'EOF'
#!/bin/expect -f

set force_conservative 0  ;# set to 1 to force conservative mode even if
			  ;# script wasn't run conservatively originally
if {$force_conservative} {
	set send_slow {1 .1}
	proc send {ignore arg} {
		sleep .1
		exp_send -s -- $arg
	}
}

set machine [lindex $argv 0];
# set timeout inlimited (change it after we know the right time)
set timeout 3600
spawn /bin/bash
match_max 100000

# login to console
send "virsh console $machine\r"
expect -exact "Escape character is ^\]\r
"
send -- "\r"

# Send Enter in boot menu
expect {
"CentOS" {send "\r" }
"<Enter>" {send "\r"}
}     

# wait for ISO installation to finish
expect -exact "\r
ce-1 login: "
send -- ""
EOF

	expect $expect_file $VM_NAME

	end_function
}

function clean_variables()
{
	para_fun_l $*; start_function clean_variables "Clean parameters from env file"

	remove_from_env_file VM_NAME
	remove_from_env_file VM_NAME_GROUP
	remove_from_env_file NUMA_ID
	remove_from_env_file DATA_INTERFACES
	remove_from_env_file IPADDR_GUEST
	remove_from_env_file IPADDR_GUEST6
	remove_from_env_file GUEST_ISOL_CORES_ID
	remove_from_env_file GUEST_ISOL_HYPER_CORES_ID
	remove_from_env_file GUEST_CORES_ID
	remove_from_env_file GUEST_HYPER_CORES_ID
	remove_from_env_file VM_IMG_PATH
	remove_from_env_file VM_SIZE
	remove_from_env_file VM_COREDUMP_PATH
	remove_from_env_file COREDUMPS_SIZE
	remove_from_env_file ISO_FILE
	remove_from_env_file PRE_VM
	remove_from_env_file PRE_VM_GROUP
	remove_from_env_file FIRST_CELERITY_VM
	remove_from_env_file SECOND_CELERITY_VM
	remove_from_env_file NUMA_1_MEM
	remove_from_env_file NUMA_0_MEM
	remove_from_env_file MEMORY
	remove_from_env_file NUMBER_GUEST_CORES
	remove_from_env_file VM_NAME_GROUP_FAMILY

	run_com_if -Ee "-e $REPORT" "cp $REPORT $REPORT.$IPADDR_HOST"
		
	end_function
}

# Function for preparing VM.conf
############################################

function config_vm_conf()
{
	para_fun_l $*; start_function config_vm_conf "Prepare file '$conf_file'"

	[[ $configFlag = 1 ]] && check_before_run_$fun
	
	echo -e "# File $conf_file for configuring VM template\n" > $conf_file
	echo -e "# Variables from $env_file\n"  >> $conf_file
	sed 's/^/ENV-PRE=/' $env_file >> $conf_file
	echo -e "\n# File $fast\n" >> $conf_file
	sed 's/^/FAST-PATH=/' $fast >> $conf_file
	echo -e "\n# File $peerapp\n" >> $conf_file
	sed 's/^/PEERAPP=/' $peerapp  >> $conf_file
	
	SUCCESSFlag=1

	end_function
}

# FCONFIG NEWVM
########################################################################################

# Function for config the new VM
############################################

function config_new_vm()
{
	para_fun_l $*; start_function config_new_vm "Prepareing new VM"
	
	check_before_run_$fun
	 
	virsh_stop
		
	echo_log -a "First time installation"

	guestfish -a $VM_IMG_PATH -i rm $PA_FIRSTBOOT
				
	load_env_file FAST-PATH
	load_env_file PEERAPP
	load_file env-pre.sh /root
	
	config_eth
		
	virsh_stop
	
	SUCCESSFlag=1

	end_function
}

# Function for copying env files
############################################

function load_env_file()
{
	para_fun_l $*; start_function load_env_file "Load env files to VM"
	
	string_file=$1
	file=`echo $string_file | tr '[:upper:]' '[:lower:]'`
	file="$file.env"
	
	echo_log -a "Loading file '$file' from file '$conf_file'."
	
	grep "^$string_file=" $conf_file | sed "s/^$string_file=//" > $VM_IMG_DIR/$file
	virt-copy-in -d $VM_NAME $VM_IMG_DIR/$file  /usr/local/etc/
	mes_return_exit "virt-copy-in Failed"

	end_function
}

# Function for copying env files
############################################

function load_file()
{
	para_fun_l $*; start_function load_file "Load file to VM"
	
	file=$1
	dir=$2
	
	echo_log -a "Loading file '$file' from '$conf_file' to directory '$dir'."
	
	grep "^ENV-PRE=" $conf_file | sed "s/^ENV-PRE=/export /" > $VM_IMG_DIR/$file
	virt-copy-in -d $VM_NAME $VM_IMG_DIR/$file $dir
	mes_return_exit "virt-copy-in Failed"

	end_function
}

# Function for configuring network on new VM + NET_ISOLATED + STORAGE
############################################

function config_eth()
{
	para_fun_l $*; start_function config_eth "Configure eth0"
	
	eth0_file_out=$VM_IMG_DIR/ifcfg-eth0
	
	virt-copy-out -d $VM_NAME $eth0_file $VM_IMG_DIR
	mes_return_exit "virt-copy-out Failed"
	
	if [[ `grep -c IPADDR0= $eth0_file_out` = 1 ]]; then
		ext_0=0
		ext_1=1
	else
		ext_0=
		ext_1=
	fi

	define_add IPADDR_GUEST IPADDR $ext_0
	define_add DEFAULTGW GATEWAY $ext_0
	define_add DNS DNS $ext_1
	define_add PREFIX PREFIX $ext_0

	configure_eth IPADDR $ext_0
	configure_eth GATEWAY $ext_0
	configure_eth DNS $ext_1
	configure_eth PREFIX $ext_0
	
	sed -i '/HWADDR/d' $eth0_file_out
	virt-copy-in -d $VM_NAME $eth0_file_out $nic_dir
	mes_return_exit "virt-copy-in Failed"

	end_function
}

# Function for replacing addresses in config_eth()
############################################

function define_add()
{
	var_in_file=$1
	var=$2
	ext=$3
	
	var_in_file=`grep $var_in_file= $conf_file | awk -F= '{print $2}'`
	[[ "X$var_in_file" = "X" ]] && \
		mes_error_exit "Variable '$var_in_file' not defined in $conf_file"
	eval "export $var$ext=\$$var_in_file"
}


# Function for replacing addresses in config_eth()
############################################

function configure_eth()
{
	var=$1
	ext=$2
	eval addr=\$$var$ext
	
	sed -i "s/$var$ext=.*/$var$ext=$addr/" $eth0_file_out
}



# Function for old cpu
############################################

function old_cpu() 
{	
	para_fun_l $*; start_function old_cpu "Old cpu sandby need update"

	define_var -Ee grep_old_cpu "E5530|E5630"
	define_var_if_else -Ee new_old_cpu "`echo \"$CPU_MODEL\" | egrep -c \"$grep_old_cpu\"` = 0" "new" "old"
	run_com_if -Ee "$new_old_cpu = old" "echo 'options vfio_iommu_type1 allow_unsafe_interrupts=1' > /etc/modprobe.d/vfio_iommu_type1.conf"

	end_function
}

# Function finding hugepages

function config_update_memory()
{
	para_fun_l $* ; start_function config_update_memory "Update memory"
	
	config_memory
	
	for vm in `echo $VM_LIST | tr ',' ' '`; do

		echo_log "Upadate memory on VM '$vm'"

		pre_vm
	
		virsh_stop
	
		run_com -Ee "virsh dumpxml $VM_NAME > $temp_xml"
		
		replace_str_4_file -Ee $temp_xml "memory unit=.*" "<memory unit='KiB'>$MEMORY</memory>"
		replace_str_4_file -Ee $temp_xml "currentMemory unit.*" "<currentMemory unit='KiB'>$MEMORY</currentMemory>"
		run_com -Ee "virsh define $temp_xml"
		
		virsh_start
	done
	
	end_function
}


# Function for adding disks to system
############################################

function config_add_data_webcache_disk()
{
	para_fun_l $*; start_function config_add_data_webcache_disk "Add data and webcache"
	
	if [[ `echo $VM_LIST | grep -c ub` = 0 ]]; then
		display -A "Run on 'ub' VM"; end_function; return
	fi
	
	define_var -Ee VM_NAME "ub"
	
	virsh_stop
	
	config_list_data_webcache_disk
	config_data_webcache_disk
	
	virsh_start
	
	config_local_storage_data
	config_local_storage_webcache

	end_function
}

# Function for configure VM and host addresses
############################################

function config_show_vm_on_host()
{
	para_fun_l $*; start_function config_show_vm_on_host "Show VM list on HOST"
	
	define_var_if_else -Ee silent_mode "\"X$1\" = \"X\"" "0" "1"
		 
	run_com -Ee "virsh list --all >$temp"
	show_file -Ee $temp "VM list on host"
	
	var -Ee VM_LIST_ON_HOST "virsh list --all | egrep -v 'Id|--|^\$' | awk '{print \$2}' | tr '\n' ' '"
	
	define_var -Ee message_list_vm "Current VM on HOST: '$VM_LIST_ON_HOST'"
	[[ $silent_mode = 1 ]] && echo_log "$message_list_vm"

	end_function
}

# Function for adding disks to system
############################################

function config_update_nic_data()
{
	para_fun_l $*; start_function config_update_nic_data "Upadte nic cards"
	
	replace_char_by_char_4_var -Ee VM_LIST "," "space"
	
	for vm in $VM_LIST; do

		if [[ $vm = pad ]]; then

			display -Wf "No NIC's on VM '$VM_NAME'"
			next
		fi
			
		echo_log "Upadate NIC's DATA on VM '$vm'"

		pre_vm
	
		virsh_stop

		virsh_start
	done

	end_function
}

# Function for creating flag in VM
############################################

function create_flag_in_vm()
{
	para_fun_l $*; start_function create_flag_in_vm "Create flag file '$1'"
	
	file=.${1}Flag
	
	touch /root/$file

	pushd /root
	virt-copy-in -d $VM_NAME $file /root
	mes_return_exit "virt-copy-in Failed"
	guestfish -a $VM_IMG_PATH -i rm $PA_FIRSTBOOT
	popd	

	end_function
}


# Function for creating flag in VM
############################################

function config_start_vm()
{
	para_fun_l $*; start_function config_start_vm "Start VM"

	define_var -Ee install_isoFlag 0
	define_var_if -Ee install_isoFlag "$VM_NAME_GROUP_FAMILY = CELERITY && ! -e $ISO_FILE" "1"
	define_var_if -Ee install_isoFlag "$VM_NAME_GROUP = PAD && ! -e $ISO_FILE" "1"

	if [[ $install_isoFlag = 1 ]]; then
   		display -Wf "No ISO file '$ISO_FILE'"
    fi

	export_env -Ee
	
	virsh_start

	end_function
}


# Function for updating logrotate for serial console log files
###############################################################

function config_logrotate()
{
	para_fun_l $*; start_function config_logrotate "Updating logrotate for serial consoles"

	export_env -Ee
	
	mkdir -p /var/log/consoles/
	cat > /etc/logrotate.d/serial_consoles << EOF
/var/log/consoles/*.log {
        weekly
        missingok
        rotate 4
        compress
        delaycompress
        copytruncate
        minsize 100k
}
EOF

	systemctl restart rsyslog.service
	end_function
}

# Function Installing OS on VM
############################################

function config_install_vm()
{
	para_fun_l $*; start_function config_install_vm "Install operating system and more"

	if [[ $VM_NAME_GROUP_FAMILY = CELERITY || $VM_NAME_GROUP = PAD ]]; then
   		display -Wf "sleep 5" "Please complete the $VM_NAME installation from the virt-mnager."; end_function; return
    fi

	expect_file=/tmp/expect
		
cat > $expect_file << 'EOF'
#!/bin/expect -f

set force_conservative 0  ;# set to 1 to force conservative mode even if
			  ;# script wasn't run conservatively originally
if {$force_conservative} {
	set send_slow {1 .1}
	proc send {ignore arg} {
		sleep .1
		exp_send -s -- $arg
	}
}

set machine [lindex $argv 0];
# set timeout inlimited (change it after we know the right time)
set timeout 3600
spawn /bin/bash
match_max 100000

# login to console
send "virsh console $machine\r"
expect -exact "Escape character is ^\]\r
"
send -- "\r"

# Send Enter in boot menu
expect {
"CentOS" {send "\r" }
"<Enter>" {send "\r"}
}     

# wait for ISO installation to finish
expect -exact "\r
ce-1 login: "
send -- ""
EOF

	expect $expect_file $VM_NAME

	end_function
}

# Function running at exit
############################################

function at_exit()
{
	case $script_name in
		deploy-virtsrv-pre.sh)
			if [[ $halt_SUCCESSFlag = 0 ]]; then
				read ans
				[[ $ans = y ]] && halt || exit_num=1
			fi
			;;
		config_backup_vm.sh)
			#In case of exit with errot umont the VM
			if [[ -n $mount_dir ]]; then	
				if [[ `df -h | grep -c $mount_dir` = 1 ]]; then	
					cd /
					guestunmount $mount_dir
					display_if_not -E "\$? = 0" "Guest is still mount"
				fi
			fi
		;;
	esac
}


#main
########################################################################

export_env -Ee

out_dir=$VM_IMG_DIR/VM_backup
out_dir_tar=$VM_IMG_DIR/VM_backup_tar
mount_dir=$VM_IMG_DIR/mount_guest
eth0=ifcfg-eth0
eth0_file=$nic_dir/$eth0
tgz_name=out_dir.tgz
tgz_file=$VM_IMG_DIR/$tgz_name
ONE_NUMA_CPU_MODEL=" Intel(R) Xeon(R) CPU E5-2620 v4 @ 2.10GHz"

echo_log "\n****** Run with parameter '$1'\n"
echo_log -l "script_name=$script_name"
define_var_if -Ee SCRIPT_NAME "-z \"$SCRIPT_NAME\"" "$script_name"
echo_log -l "SCRIPT_NAME=$SCRIPT_NAME"
define_var_if -Ee deploy_script "$SCRIPT_NAME = deploy-firstboot-config-host-guest" "deploy-firstboot-config-host-guest"
[[ $1 = config_vm_list || $1 = config_ub_celerity_pad ]] && clean_variables
[[ $SCRIPT_NAME = deploy-firstboot-config-host-guest ]] && check_common_vars
check_function_vars $1

case $1 in
	#### deploy-host.sh
	##########################################################

	# Copy file from /root
	config_distribute_files)		config_distribute_files ;;
	
	# Copy RPM's to repo directory
	config_copy_rpms_2_repo)		config_copy_rpms_2_repo ;;
	
	# Copy iso
	copy_iso)						copy_iso ;;

	# Install_host_step_1.yml 
	# 1. config_add_repo
	# 2. Install RPM's
	# 
	# Install_host_step_2.yml
	# 1. install_tree.tgz
	# 2. chown to padmin
	
	# Install_host_step_3.yml
	config_ipv6)					config_ipv6 ;;
	config_dracut)					config_dracut ;;
	config_utilities)				config_utilities ;;
	
	# Install_host_step_4.yml
	# Disables/enables services
	# firewalld enabled=no
	# firewalld enabled=no
	# ip6tables enabled=yes

	# Install_host_step_5.yml
	# Restart the system
	
	#### deploy-grub.sh
	##########################################################

	# for installing VM list
	config_vm_list)					config_vm_list ;;
	config_host_cores)				config_host_cores ;;
	config_numa_id_4_vm)			config_numa_id_4_vm ;;
	config_data_nics)				config_data_nics ;;
	
	# Install_grub_step_1.yml
	config_update_fstab)            config_update_fstab ;;
	config_product)					config_product ;;
	config_host_isol_cores)			config_host_isol_cores ;;
	config_grub)					config_grub ;;
	config_hugepages)				config_hugepages ;;
	
	#### deploy-guest.sh
	##########################################################

	config_ub_celerity_pad)			config_ub_celerity_pad ;;
	config_network_4_vm)			config_network_4_vm ;;
	
	# install_guest_step_1.yml

	#XML FILE
	config_vm_system_disk)				config_vm_system_disk ;;
	config_vm_coredump_disk)			config_vm_coredump_disk ;;
	config_memory_vm)					config_memory_vm;;
	config_guest_cores)					config_guest_cores ;;
	config_xml_skeleton)				config_xml_skeleton ;;
	config_virt_clone)					config_virt_clone ;;
	config_local_disk)					config_local_disk ;;
	config_coredumps_disk)				config_coredumps_disk ;;
	config_local_cdrom)					config_local_cdrom ;;
	config_guest_mgmt)					config_guest_mgmt ;;
	config_isolated_network)			config_isolated_network ;;
	config_local_nics)					config_local_nics ;;
	config_list_data_webcache_disk) 	config_list_data_webcache_disk ;;
	config_prepare_data_disks_list)		config_prepare_data_disks_list ;;
	config_prepare_webcache_disks_list)	config_prepare_webcache_disks_list ;;
	config_data_webcache_disk)			config_data_webcache_disk ;;
	config_local_storage_data)			config_local_storage_data ;;
	config_ssd_partition_for_vd) 		config_ssd_partition_for_vd ;;
	config_local_storage_webcache)		config_local_storage_webcache ;;
	config_guest_isol_cores)			config_guest_isol_cores ;;
	config_fast_path)					config_fast_path ;;
	config_celerity_mac_reorder)    	config_celerity_mac_reorder ;;
	#End XML FILE
	
	# install_guest_step_2.yml

	config_logrotate)				config_logrotate ;;
	config_start_vm)				config_start_vm ;;
	config_install_vm)				config_install_vm ;;
	# Show information
	show_xml_file)					show_xml_file ;;
	
	# From script
	clean_variables)				clean_variables ;;
	pre_vm)							pre_vm $2 ;;

# More
	config_update_memory)			config_update_memory ;;
	config_add_data_webcache_disk)	config_add_data_webcache_disk ;;
	config_update_nic_data)			config_update_nic_data ;;
	config_replace_data_webcache_disk)	config_replace_data_webcache_disk ;;
	config_replace_system_disk)		config_replace_system_disk ;;
	config_backup_vm)				config_backup_vm ;;
	config_restore_vm)				config_restore_vm ;;
	
	*) display -Ee "First parameter to script '$1' not found" ;;
esac

exitScriptFlag=1
exit 0