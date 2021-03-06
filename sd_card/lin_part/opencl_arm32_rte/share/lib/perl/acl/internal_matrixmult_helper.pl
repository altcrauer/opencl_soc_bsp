# (C) 1992-2014 Altera Corporation. All rights reserved.                         
# Your use of Altera Corporation's design tools, logic functions and other       
# software and tools, and its AMPP partner logic functions, and any output       
# files any of the foregoing (including device programming or simulation         
# files), and any associated documentation or information are expressly subject  
# to the terms and conditions of the Altera Program License Subscription         
# Agreement, Altera MegaCore Function License Agreement, or other applicable     
# license agreement, including, without limitation, that your use is for the     
# sole purpose of programming logic devices manufactured by Altera and sold by   
# Altera or its authorized distributors.  Please refer to the applicable         
# agreement for further details.                                                 
    


# Altera SDK for HLS compilation.
#  Inputs:  A .cpp file containing all the kernels
#  Output:  A subdirectory containing: 
#              Design template
#              Verilog source for the kernels
#              System definition header file
#
# 
# Example:
#     Command:       acc foobar.cpp
#     Generates:     
#        Subdirectory foobar including key files:
#           *.v
#           <something>.qsf   - Quartus project settings
#           <something>.sopc  - SOPC Builder project settings
#           kernel_system.tcl - SOPC Builder TCL script for kernel_system.qsys 
#           system.tcl        - SOPC Builder TCL script
#
# vim: set ts=2 sw=2 et

      BEGIN { 
         unshift @INC,
            (grep { -d $_ }
               (map { $ENV{"ALTERAOCLSDKROOT"}.$_ }
                  qw(
                     /host/windows64/bin/perl/lib/MSWin32-x64-multi-thread
                     /host/windows64/bin/perl/lib
                     /share/lib/perl
                     /share/lib/perl/5.8.8 ) ) );
      };


use strict;
require acl::File;
require acl::DSE;
require acl::Pkg;
require acl::Env;

my $prog = 'acc';
my $return_status = 0;

#Filenames
my $input_file = undef; # might be relative or absolute
my $output_file = undef; # -o argument
my $srcfile = undef; # might be relative or absolute
my $objfile = undef; # might be relative or absolute
my $pkg_file = undef;
my $absolute_srcfile = undef; # absolute path

#directories
my $orig_dir = undef; # absolute path of original working directory.
my $work_dir = undef; # absolute path of the project working directory as is.

# Executables
my $clang_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-clang";
my $opt_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-opt";
my $link_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-link";
my $llc_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-llc";
my $sysinteg_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/system_integrator";

#Flow control
my $parse_only = 0; # Hidden option to stop after clang.
my $link_only = 0; # Hidden option to stop after clang.
my $opt_only = 0; # Hidden option to only run the optimizer
my $ip_only = 0; # Hidden option to only run the optimizer
my $llc_only = 0; # Hidden option to only run the optimizer
my $verilog_gen_only = 0; # Hidden option to only run the Verilog generator
my $ip_gen_only = 0; # Hidden option to only run up until ip-generate, used by sim
my $skip_qsys = 0; # Hidden option to skip the Qsys generation of "system"
my $emulator_flow = 0;
my $RTL_flow = 0;
my $simulator_flow = 0;
my $compile_step = 0; # stop after generating .aoco

#Output control
my $verbose = 0; # Note: there are two verbosity levels now 1 and 2
my $report = 0; # Show Throughput and area analysis
my $debug_option = undef; # Show debug output from various stages

my $dotfiles = 0;

# Yet unclassfied
my @cmd_list = ();
my $root_name = undef;
my $disassemble = 0; # Hidden option to disassemble the IR
my $triple_arg = '';

# Regular arguments.  These go to clang, but does not include the .cl file.
my @user_clang_args = ();
my @user_linkflags =();
# The compile options as provided by the clBuildProgram HLS API call.
# In a standard flow, the ACL host library will generate the .cl file name, 
# and the board spec, so they do not appear in this list.
my @user_opencl_args = ();

my $opt_arg_after   = ''; # Extra options for opt, after regular options.
my $llc_arg_after   = '';
my $clang_arg_after = '';
my $sysinteg_arg_after = '';

my $opt_passes = '--acle ljg7wk8o12ectgfpthjmnj8xmgf1qb17frkuwwjibgl1mju7atjqllwxz2abmczpyxdtwgdotxqemawzekhznk71wyb3r1em3vbbyw0o7gybmay7atjfnljxwgpsmvwogxfbwepii2qqqh07ekh3nj8xbrkhmzpzxrko0yvm7jlzquvzuchmljpb1rkhqb17frkc0rdo880qqkyzuhdfnfy3xxf7m88zt8vs0rjiory1muy7atjolf0b1xfclb17frkm0t8zr2q1mu07ekh3nrwxc2f1qovp3xd38uui32qclkjpatdzqkpbcrk33czpyxjb0tjo1gu7qgwpk3h72tfxmgssm80oyrgkwrpii2wctgfpttdqnq0bvgsom7jzerj38uui3xuolrdpe3bknyycprzbtijze2ds0rjzbrlqqjwo0hd3quu3xxf1q8vz3gff0ewiw2qems07ekh3njvc7ra1q8dolxfh0uui3ruzlj07ekh3nt8clraunczpyrk77uvm7jlzqu8pfcdfnedcfgpsmv0pggk70tjipructgfpthgomq0b18a7q3wp12j1wupiirwctgfpt3jzqhpbz2fbl38z3gffwhpom2e3ldjpacvorlvcmxaml88zs2kc7ujo7jlzmyposcdmnr8cygsfqiw7ljg70gpizxutqddzbtjbnr0318a7mzpp8xd70wdi22qqqg07ekh3lh8czra7mb0ps2jh0qdi880qqkvok3h7qq8x2gh7qxvzt8vs0r8z72ezlujpt3gmlhyc0jpsmv0pdrg37uui3guemr8z03k72tfxmraumv8pt8vs0rjiorlclgfpt3fknjjbzrj7qz87frkceq8z7ruhqswpw3bklt010jpsmv0pdrg37uui32yqqujokcf3le0318a7mzpp8xd70wdi22qqqg07ekh3nedx82j1q8jot8vs0rjiorlclgfpt3gznejxbrzbtijzsrgfwhdmire3qgwpecfqnldx0jpsmvvz7gg38uui32l1qavz83ahlkwb0jpsmvjoyrk3etfmirekmsvo0tjhnqpcz2abqb17frkq0kdiy20qqkwojhdonuwcz2azqb17frk70w8zr2wtqjwoeckorlvcw2kfq1yzw2kc7qwiix713svzwtdoluu3xxf1qcjzlxbbyw0ot2qumywpkhkqmydc3rzbtijzggg7ek0oo2loqddpecvorlvcqrjmnzwoljg7wudo1xw13svz8hdhlhjxygh3ncjot8vs0rwoprloqjwpwtjoluu3xxf7mipp8xdk0u8zm2wctgfpthjmljpbzgdmlb17frkbew8zoxltqgfpttjenudxxgdhm8w7ljg7wewioxu13svz33gslkwxz2dulb17frkh0r0zt2ectgfptchhnl0b18a7m3pp1rghwevm7jlzqu8pfcdfnedcfxfomxw7ljg70g0o3xuctgfpttkbql0318a7mo8zark37swiyxyctgfpt3gknjwbmxakqvypf2j38uui3gq1la0oekh3lh0xlgd1qcypfrj38uui3xwzlg07ekh3nuwcmgd33czpyrfu0evzp2qmqwvzltk72tfxmgssm80oyrgkwrpii2wctgfpttdzqj8xwgpsmv0zl2kc0uui3xuolswoscfqqkycqrzbtijzwxgfwrpopxwzqg07ekh3nyjxxxkcno8z1rjbwtfmireoqjpo23golj0318a7mb0p02ku7gdmirekmswpkhholuu3xxf7l3dogxfs0lvm7jlzmsjp23h1mtwb0jpsmv8plgfz0u8z7xy1nudpy1bkny8xxrjbq8pzrrkb0gvm7jlzmgjzn3foluu3xxf1mv0pljg7wewi1xw13svz3cfhljyc18a7mzppmgfuww0zbrezlgfpt3jzlt0318a7qzyzfxjh0udmire1mh8pt3jflqvb0jpsmv0o12ks0gyooguuqgfpt3kbnevc7rahm8w7ljg7wewiq2wolkjpahf72tfxmrd7mcw7ljg7wewiq2wolkjpatdzquu3xxf1qovor2s77uui3gu1qajpn3korlvcbgdkmczpy2hswk8zbglzldvz3cvorlvclgdkmipol2vs0rwioge13svzutj3ntvbqgd7lb17frkc0rdo880qqkvot3jfnupblgd3low7ljg7wu0o7x713svz8hdqlgp1lgdzqb17frkm7udiogy1qgfpt3gknewbzgfhmzdirxdu0wyi7jlzquwoshdonj0318a7q1dod2gfwkdoygukmt07ekh3nuwcmgd33czpyxft0qdmirezqs8zd3k3my8xxxd33czpy2hs0gjz3rlumk8pa3k72tfxmrd7mcw7ljg7wypij2yclgfpthjqlhvc7xkcn8w7ljg7wedi72l13svz3cdfnewbygdmlb17frko7u8zbgwknju7atjknlpbbra7lb17frk1wkjzr2qoqrwoecd1ml0b7xd1q3ypdgg38uui3rwmns07ekh3ltvc1rzbtijz82hkwhjibgwklkdzqcvorlvcvxkcl88oyxduwypp880qqk8patdzmyjxb2fuqi8zljg7wwwi7jlzmt07ekh3njvc7ra1q8ypb2jbyw0op2eolhyzekh3nujc32kbmxyzm2j7etfmirezlk8zd3j1qjycwra33czpyxj70uvm7jlzmh8pv3f7mtfxm2fuq3jzrrfc7gvm7jlzmajpm3k1mjjbzrj7qzw7ljg70g0o1xlbmu8px3k72tfxmrd7mcw7ljg70tjo32wctgfpttkbql0318a7qcjzlxbbyw0obglznrvzs3h1nedx1rzbtijz3gff0y8z12l13svzqchhly8cvgpsmv8pl2g38uui3xuolsjz23jsntfxmxdhmidzrxgbyw0oz2wuqgfpt3f3mujc1rzbtijzmgfuwjpi1xl13svzf3jzqe0318a7mxpofxbbyw0ot2qumywpkhkqmtfxm2d3lb17frkc0rdo880qqk8packolfvbtgf3l1ypfrj38uui3rykqdvzfcvorlvcy2k1qijoergm7edmirecnu8pacfbluu3xxfhmivp32vs0r0zb2lcna8pl3a72tfxmra7m8jorxbbyw0oz2wtqsjp8cvorlvcrgdmnzpzxxbbyw0oprlemyy7atj3meyxwrauqxyit8vs0rji3ruzlj07ekh3lypc22kbm187frk1wwyioxybmryzy1bknywccrjbtijzygjz0uui3geomhpoe3d72tfxm2fmnbppyxhbyw0o3rlqmtyz2tdqnldxlyzbtijzqrkbwtfmirekmsvo0tjhnqpcz2abqb17frk1wwyioxybmryzekh3ny0x72asmc0pljg7wudoy2wqmgyzatjqntvb0jpsmvpolrkc7w8zbgt1qgfpttgoljdx1ra33czpygdbwgpin2tctgfpttkbql0318a7mzpp8xd70wdi22qqqg07ekh3ltvc1rzbtijz72jm7qyokx713svz23ksnldb1gpsmv0zl2kc0uui3ru3lspoetd72tfxmrd7mcw7ljg7wjdor2qmqw07ekh3nqyclxdbmczpyxfm7ujobrebmryzw3bknyvbyxamncjot8vs0rjo32wctgfpt3gknjwbmxakqvypf2j38uui3gu1mywpktjmlhyc18a7qojonxbbyw0o1xwzqg07ekh3lq8xmga33czpyxgf0wvz7jlzqkjpfhjqllyc0jpsmv0pgrkkwtfmiremlgpokhkqquu3xxfhmivp32vs0rjzr2qclkjp7hhzmtfxmgfsqivpm2kc7uvm7jlzqkpz8cvorlvcrgdmnzpzxxbbyw0obglznrvzs3h1nedx1rzbtijzwgdswtfmirezldyp8chqlr8vm2dzqb17frkk0u8zm2wolgwo7hdkluu3xxf7nz8p3xguwypp3gw7mju7atjfnljb12k7n2ypmrktwtfmire7mtdpy1bknywblgsonzyzs2vs0rdi1xyhmju7atjznyyc0jpsmvyzfggfwkpow2w13svztthmlqycqxfuqivzljg7wrwiegl3qu07ekh3lk8xmxsbtijzsrg70tji7jlzqayzf3bknyvcc2aomzvzt8vs0ryz7gukmh8iy1bknywxzxfkqb17frko7u8zbgwknju7atj3my8cvgfml88zq2d7wkpioglctgfpthdoltybmgdbtijz12j77wdzrre1qu07ekh3ltvc1rzbtijz72jm7qyokx713svzuckunhvbygpsmvjoggsb0gvm7jlzqt8pktjsluu3xxf7nz8p3xguwypp3gw7mju7atjfnljb12k7n2ypmrktwtfmireoqjpo23goljvbyghhmcw7ljg7wu0o7x713svzdthmltvbyxamncjom2sh0uvm7jlzmuyzf3jzmtpbzgfhmzdilxbbyw0o0re1mju7atjsntyxc2kun80o12j10epiirwctgfptchhnuwcqrjfq88z8xdueedo880qqkvzshhbmtpbygpsmvypfxdb0ydor20qqkyp7chzme0bvgsbq8jot8vs0rpiiru3lkjpfhjqllyc0jpsmv0zy2j38uui32e3mfyo3cforlvcqgsqncjot8vs0ryz7gukmh8iy1bknydcwgpsmvwprgfc0uyi7xwctgfpthkomjyc18a7q3dogrjfwwwiz2w3nu8pt3bknydcu2a7q3ypdgg7etfmiremqrvoe3bkny8c8rd7n3dzljg7wydzire3ldjpatd72tfxmrdfm3dzs2jbyw0oy2yumyy7atjblky3xxfbliypmxbbyw0obglznrvzs3h1nedx1rzbtijzqrkbwtfmiremmyvzekh3ltycmxakq1vp82hc7qwiix713svzkhh3qhvccgammzpplxbbyw0o0re1mju7atjblkvc18a7mvvpfgdbwg0zbrlqqgfptcdomj0x0jpsmvpz3rkbyw0o3rlqmtyz2tdqnldx18a7q88zargo7tji880qqk8patdzmyjxb2fuqi8zt8vs0rjo32wctgfpthk7myy3xxfcm7ppr2gu0rdmirebma8pqhh72tfxmgssm80oyrgkwrpii2wctgfptck3nt0318a7mxpofxbbyw0ot2qumywpkhkqmtfxm2d3lb17frkc0rdo880qqkpoeckomyyc18a7qc8z32jswudoire1qgfptckqnjwb72a7mcw7ljg7wewioxu13svz33gslkwxz2dulb17frk1wg8z12t13svz8hdqlg0318a7q88zargo7udmire1nsjouhhzmtwc18a7mvyzsxg7etfmiretqs8zwtdzmlpb1xkcn70plxbbyw0orrltmay7atj7me0b1rauqi8zt8vs0rpiiru3lkjpfhjqllyc0jpsmv0zy2j38uui32eqmsjp03jzmty3xxfkmc8pq2j3etfmireznadoy1bknydc2xjcqb17frk3egdo7jlzmajpscdorlvcwgs3nc0pggguwwwo880qqkpoe3hhlgyc18a7qc8o3xgu0rpow2w13svzwhjcluu3xxfzq2ppt8vs0rpiiru3lkjpfhjqllyc0jpsmvyzqrkbwtfmirezlk8pncvorlvcvxafq187frk37qvz7xlkms8patk72tfxmgssm80oyrgkwrpii2wctgfptck3nt0318a7q88zargo7udmire3qr0od3g3nuwb1gpsmv0zurj38uui3rukqa0od3gbnfvc2xd33czpyxgf0jdorru7ldwotcg72tfxmrdfq387frk7wywo7jlzmajpscdorlvcwgs3nc0pggguwwwo880qqk8zwhgomjwb18a7m8ypb2j7etfmiremlgpokhkqquu3xxfoqovprxduwwwoyrlkmswo3cfqqqyc0jpsmvjz12j1wkdo7jlzquwouchfntfxm2dmnc8zljg70rjieru3lgpo3cvorlvcn2kbmbjpljg70edozxw1my07ekh3ltvc1rzbtijz12j77wdzrre1qgfpttdenupbz2azqb17frkceq8zo2y7md0o7cforlvcw2kuqi0ot8vs0ryz7gukmh8iy1bknydcwxd1q28z12ho0svmijn';

# device spec differs from board spec since it
# can only contain device information (no board specific parameters,
# like memory interfaces, etc)
my $device_spec = "";

# On Windows, always use 64-bit binaries.
# On Linux, always use 64-bit binaries, but via the wrapper shell scripts in "bin".
my $qbindir = ( $^O =~ m/MSWin/ ? 'bin64' : 'bin' );

# For messaging about missing executables
my $exesuffix = ( $^O =~ m/MSWin/ ? '.exe' : '' );
my $dash_g = 0;      # Debug info enabled? 

sub append_to_log { #filename ..., logfile
  my $logfile= pop @_;
  open(LOG, ">>$logfile") or mydie("Couldn't open $logfile for appending.");
  foreach my $infile (@_) {
    open(TMP, "<$infile")  or mydie("Couldn't open $infile for reading.");
    while(my $l = <TMP>) {
      print LOG $l;
    }
    close TMP;
  }
  close LOG;
}

sub mydie(@) {
  print STDERR "Error: ".join("\n",@_)."\n";
  chdir $orig_dir if defined $orig_dir;
  unlink $pkg_file;
  exit 1;
}

sub myexit(@) {
  print STDERR "Success: ".join("\n",@_)."\n";
  chdir $orig_dir if defined $orig_dir;
  exit 0;
}

# Functions to execute external commands, with various wrapper capabilities:
#   1. Logging
#   2. Time measurement
# Arguments:
#   @_[0] = { 
#       'stdout' => 'filename',   # optional
#        'title'  => 'string'     # used mydie and log 
#     }
#   @_[1..$#@_] = arguments of command to execute

sub mysystem_full($@) {
  my $opts = shift(@_);
  my @cmd = @_;

  my $out = $opts->{'stdout'};
  my $title = $opts->{'title'};
  my $err = $opts->{'stderr'};

  if ($verbose >= 2) {
    print join(' ',@cmd)."\n";
  }

  # Replace STDOUT/STDERR as requested.
  # Save the original handles.
  if($out) {
    open(OLD_STDOUT, ">&STDOUT") or mydie "Couldn't open STDOUT: $!";
    open(STDOUT, ">>$out") or mydie "Couldn't redirect STDOUT to $out: $!";
    $| = 1;
  }
  if($err) {
    open(OLD_STDERR, ">&STDERR") or mydie "Couldn't open STDERR: $!";
    open(STDERR, ">>$err") or mydie "Couldn't redirect STDERR to $err: $!";
    select(STDERR);
    $| = 1;
    select(STDOUT);
  }
  print STDOUT "============ ${title} ============\n" if $verbose>1; 
  # Run the command.
  system(@cmd) == 0 or mydie("HLS $title FAILED.\n");
 
  # Restore STDOUT/STDERR if they were replaced.
  if($out) {
    close(STDOUT) or mydie "Couldn't close STDOUT: $!";
    open(STDOUT, ">&OLD_STDOUT") or mydie "Couldn't reopen STDOUT: $!";
  }
  if($err) {
    close(STDERR) or mydie "Couldn't close STDERR: $!";
    open(STDERR, ">&OLD_STDERR") or mydie "Couldn't reopen STDERR: $!";
  }

#  if($out ) {
#      move_to_err_and_log($err,$out);
#  }
  return $?
}

sub mysystem_redirect($@) {
  # Run command, but redirect standard output to $outfile.
  my ($outfile,@cmd) = @_;
  return mysystem_full ({'stdout' => $outfile}, @cmd);
}

sub mysystem(@) {
  return mysystem_redirect('',@_);
}

sub save_pkg_section($$$) {
   my ($pkg,$section,$value) = @_;
   # The temporary file should be in the compiler work directory.
   # The work directory has already been created.
   my $file = $work_dir.'/value.txt';
   open(VALUE,">$file") or mydie("Can't write to $file: $!");
   binmode(VALUE);
   print VALUE $value;
   close VALUE;
   $pkg->set_file($section,$file)
       or mydie("Can't save value into package file: $acl::Pkg::error\n");
   unlink $file;
}


sub get_acl_board_hw_path {
  return "$ENV{\"ALTERAOCLSDKROOT\"}/share/models/bm";
}


sub remove_named_files {
    foreach my $fname (@_) {
      acl::File::remove_tree( $fname, { verbose => ($verbose == 1 ? 0 : $verbose), dry_run => 0 } )
         or mydie("Could not remove intermediate files under directory $fname: $acl::File::error\n");
    }
}

sub remove_intermediate_files($$) {
   my ($dir,$exceptfile) = @_;
   my $thedir = "$dir/.";
   my $thisdir = "$dir/..";
   my %is_exception = (
      $exceptfile => 1,
      "$dir/." => 1,
      "$dir/.." => 1,
   );
   foreach my $file ( acl::File::simple_glob( "$dir/*", { all => 1 } ) ) {
      if ( $is_exception{$file} ) {
         next;
      }
      if ( $file =~ m/\.aclx$/ ) {
         next if $exceptfile eq acl::File::abs_path($file);
      }
      acl::File::remove_tree( $file, { verbose => $verbose, dry_run => 0 } )
         or mydie("Could not remove intermediate files under directory $dir: $acl::File::error\n");
   }
   # If output file is outside the intermediate dir, then can remove the intermediate dir
   my $files_remain = 0;
   foreach my $file ( acl::File::simple_glob( "$dir/*", { all => 1 } ) ) {
      next if $file eq "$dir/.";
      next if $file eq "$dir/..";
      $files_remain = 1;
      last;
   }
   unless ( $files_remain ) { rmdir $dir; }
}

sub compile {
  my ($base,$work_dir,$src,$obj,$x_file,$board_variant, $family) = @_;
  my $fulllog="$base.log";
  my $pkg_file_final = $obj;
  $pkg_file = $pkg_file_final.".tmp";
  my $run_copy_skel = 1;
  my $run_copy_ip = 1;
  my $run_clang = 1;
  my $run_opt = 1;
  my $run_verilog_gen = 1;

  if ( $parse_only || $link_only || $opt_only || $ip_only || $llc_only || $verilog_gen_only) {
    $run_copy_ip = 0;
    $run_copy_skel = 0;
  }
  
  acl::File::make_path($work_dir) or mydie("Can't create dir $work_dir: $!");

  unlink "$work_dir/$fulllog";

  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);

  # Make sure the board specification file exists. This is needed by multiple stages of the compile.
  my ($board_spec_xml) = acl::File::simple_glob( $acl_board_hw_path."/$board_variant" );
  my $xml_error_msg = "Cannot find Board specification!\n*** No board specification (*.xml) file inside ".$acl_board_hw_path.". ***\n" ;
  if ( $device_spec ne "" ) {
    my $full_path =  acl::File::abs_path( $device_spec );
    $board_spec_xml = $full_path;
    $xml_error_msg = "Cannot find Device Specification!\n*** device file ".$board_spec_xml." not found.***\n";
  }
  -f $board_spec_xml or mydie( $xml_error_msg );
  my $llvm_board_option = "-board $board_spec_xml";   # To be passed to LLVM executables.

  
  if ( $run_copy_skel ) {
    # Copy board skeleton, unconditionally.
    # Later steps update .qsf and .sopc in place.
    # You *will* get SOPC generation failures because of double-add of same
    # interface unless you get a fresh .sopc here.
    acl::File::copy_tree( $acl_board_hw_path."/*", $work_dir )
      or mydie("Can't copy Board template files: $acl::File::error");
    map { acl::File::make_writable($_) } (
      acl::File::simple_glob( "$work_dir/*.qsf" ),
      acl::File::simple_glob( "$work_dir/*.sopc" ) );
  }

  if ( $run_copy_ip ) {
    my $cmp_dir = $base;
    
    acl::File::copy_tree( acl::Env::sdk_root()."/ip/*", "$work_dir/ip/$cmp_dir/" )
      or mydie("Can't copy IP files: $acl::File::error");

    # Add SEARCH_PATH for ip/$base to the QSF file
    foreach my $qsf_file (acl::File::simple_glob( "$work_dir/*.qsf" )) {
      open (QSF_FILE, ">>$qsf_file") or die "Couldn't open $qsf_file for append!\n";
      print "$prog: Adding SEARCH_PATH assignment to $qsf_file\n" if $verbose>1;
      print QSF_FILE "\nset_global_assignment -name SEARCH_PATH \"ip/$cmp_dir\"\n";
      
      # Case:149478. Disable auto shift register inference for appropriately named nodes
      print "$prog: Adding wild-carded AUTO_SHIFT_REGISTER_RECOGNITION assignment to $qsf_file\n" if $verbose>1;
      print QSF_FILE "\nset_instance_assignment -name AUTO_SHIFT_REGISTER_RECOGNITION OFF -to *_NO_SHIFT_REG*\n";
      close (QSF_FILE);
    }
  }
  
  my $emulator_arch=acl::Env::get_arch();
  # Late environment check IFF we are using the emulator
  if (($emulator_arch eq 'windows64') && ($emulator_flow == 1) ) {
    my $msvc_out = `LINK 2>&1`;
    chomp $msvc_out; 
    if ($msvc_out !~ /Microsoft \(R\) Incremental Linker Version/ ) {
      mydie("$prog: Can't find a working version of Linker LINK.EXE\n");
    }
  }
  
  my @includepaths=("-I$ENV{\"ALTERAOCLSDKROOT\"}/include");
  push (@includepaths,"-I$ENV{\"ALTERAOCLSDKROOT\"}/host/include");
  my $absolute_srcfile = acl::File::abs_path($srcfile);
  -f $absolute_srcfile or mydie("Internal error. Can't determine absolute path for $srcfile");

  my $host_lib_path = acl::File::abs_path( acl::Env::sdk_root()."/host/${emulator_arch}/lib");
  
  if (!$RTL_flow) {
      if($emulator_flow) {
	  print "$prog: Running Testbench parser....\n" if $verbose; 
	  my @debug_options = ($debug_option);
	  my @clang_arg_after_array = split(/\s+/m,$clang_arg_after);

	  @cmd_list = (
	      $clang_exe,
	      qw(-x hls -O0 -DALTERA_CL -Wuninitialized),
	      '-DHLS_EMULATION',
	      @debug_options, 
	      $absolute_srcfile,
	      @clang_arg_after_array,
	      @includepaths,
	      '-lstdc++',
        "-L$host_lib_path",
        '-lhls_emul',
	      '-o',
	      $output_file ? "$output_file":"${base}.exe",
	      @user_clang_args,
	      @user_linkflags
	      );

	  mysystem_full(
	      {'stdout' => "$work_dir/$fulllog", 'title' => "Emulator compile"},
	      @cmd_list);
	  return;
      } else { #Simulator flow
	  print "$prog: Running Testbench parser....\n" if $verbose; 

	  my $tbclangout="$base.pre.tb.ll";
	  #Temporarily disabling exception handling here, Tracking in FB223872
	  my @clang_std_opts = qw(-S -emit-llvm  -x hls -O0 -DALTERA_CL -Wuninitialized -fno-exceptions);
	  my @debug_options = ($debug_option);
	  my @clang_arg_after_array = split(/\s+/m,$clang_arg_after);
	  
	  my @macro_options;
	  @macro_options= qw(-DHLS_COSIMULATION);
	
	  @cmd_list = (
	      $clang_exe,
	      @clang_std_opts,
	      @includepaths,
	      @macro_options,
	      @debug_options, 
	      $absolute_srcfile,
	      @clang_arg_after_array,
	      '-o',
	      "$work_dir/$tbclangout",
	      @user_clang_args,
	      );
	  mysystem_full(
	      {'stdout' => "$work_dir/$fulllog", 'title' => "Sim Testbench Clang Parse"},
	      @cmd_list);

#Already disassembled  
#	  if ( $disassemble ) { mysystem("llvm-dis \"$work_dir/$tbclangout\"" ) == 0 or mydie("Cannot disassemble: \"$work_dir/$tbclangout\"\n"); }

	  chdir $work_dir or mydie("Can't change dir into $work_dir: $!");
	  
	  my $flow_options= "-replacecomponentshlssim";

	  mysystem_full(
	      {'stdout' => $fulllog, 'title' => 'opt (host tweaks))'},
	      "$opt_exe  $flow_options $llvm_board_option $debug_option $opt_arg_after \"$tbclangout\" -o \"$base.tb.bc\"" );
	  if ( $disassemble ) { mysystem("llvm-dis \"$base.tb.bc\"" ) == 0 or mydie("Cannot disassemble: \"$base.tb.bc\"\n"); }
	    
	  my $arch_options = ();
	  if ($emulator_arch eq 'windows64') {
	      $arch_options = "-cc1 -triple x86_64-pc-win32 -emit-obj -o libkernel.obj";
	  } else {
	      $arch_options = "";
	  }
          
	  mysystem_full(
	      {'stdout' => $fulllog, 'title' => 'clang (executable emulator/simulator tb image)'},
	      "$clang_exe -B/usr/bin -fPIC -shared -Wl,-soname,${base}_sim.so -o ${base}_sim.so -O0 \"$base.tb.bc\" -lstdc++ -L$host_lib_path -lhls_cosim ".join(' ',@user_linkflags)." ".join(' ',@user_clang_args)."\n" );
      }
  } #temporary guard around testbench generation  
  my $optinfile = "$base.1.bc";
  my $pkg = undef;
  
  # OK, no turning back remove the result file, so no one thinks we succedded
  unlink "$objfile";

  # initializes DSE, used for area estimates
  acl::DSE::dse_prologue($work_dir);

  my $clangout = "$base.pre.ll";
  
  print "$prog: Running HLS parser....\n" if $verbose; 
  chdir $orig_dir or mydie("Can't change to dir $orig_dir: $!\n");
  
  my @clang_std_opts2 = qw(-S -ccc-host-triple fpga64-unknown-linux -x hls -emit-llvm -DALTERA_CL -Wuninitialized -fno-exceptions);
  my @board_options2 = map { ('-mllvm', $_) } split( /\s+/, $llvm_board_option );
#  my $includepaths2="-I$ENV{\"ALTERAOCLSDKROOT\"}/lib/clang/3.0/include/";
  my @board_def2 = ("");
  my @debug_options2 = ($debug_option);
  my @clang_arg_after_array2 = split(/\s+/m,$clang_arg_after);

  @cmd_list = (
      $clang_exe, 
      @clang_std_opts2,
      @board_options2,
      @board_def2,
      @includepaths,
      @debug_options2, 
      $absolute_srcfile,
      @clang_arg_after_array2,
      '-o',
      "$work_dir/$clangout",
      @user_clang_args,
      );
  $return_status = mysystem_full(
      {'stdout' => "$work_dir/$fulllog", 'title' => "fpga Clang Parse"},
      @cmd_list);


  if ( $parse_only ) { myexit("Parse Only"); }

  # Create package file in source directory, and save compile options.

  chdir $work_dir or mydie("Can't change into dir $work_dir: $!\n");
  
  $pkg = create acl::Pkg($pkg_file);
  save_pkg_section($pkg,'.acl.board',$board_variant);
  save_pkg_section($pkg,'.acl.compileoptions',join(' ',@user_opencl_args));
  # Set version of the compiler, for informational use.
  # It will be set again when we actually produce executable contents.
  save_pkg_section($pkg,'.acl.version',acl::Env::sdk_version());

#Already disassembled  
#  if ( $disassemble ) { mysystem("llvm-dis \"$work_dir/$clangout\"" ) == 0 or mydie("Cannot disassemble: \"$work_dir/$clangout\"\n"); }

  print "$prog: HLS parser completed successfully.\n" if $verbose;

  # Link with standard library.
  my $early_bc = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_early.bc");
  @cmd_list = (
      $link_exe,
      "$work_dir/$clangout",
      $early_bc,
      '-o',
      $optinfile );
  $return_status = mysystem_full(
      {'stdout' => "$fulllog", 'title' => "Early Link"},
      @cmd_list);

  if ( $disassemble ) { mysystem("llvm-dis \"$optinfile\"" ) == 0 or mydie("Cannot disassemble: \"$optinfile\"\n"); }

  if ( $link_only ) { myexit("Link Step"); }

  print "$prog: Compiling....\n" if $verbose;

  my $kwgid=$base.".opt.bc";
  $return_status = mysystem_full(
      {'stdout' => $fulllog, 'title' => "Main Opt pass"},
      "$opt_exe -HLS $opt_passes $llvm_board_option $debug_option $opt_arg_after \"$optinfile\" -o \"$kwgid\"");

  if ( $disassemble) { mysystem("llvm-dis \"$kwgid\"" ) == 0 or mydie("Cannot disassemble: \"$kwgid\" \n"); }

  if ( $opt_only ) { myexit("Opt Step"); }

  my $lowered=$base.".lowered.bc";
  print "$prog: Linking with IP library ...\n" if $verbose;
  # Lower instructions to IP library function calls
  
  $return_status = mysystem_full(
      {'stdout' => $fulllog, 'title' => "Lower to IP"},
      "$opt_exe -HLS -insert-ip-library-calls $opt_arg_after \"$kwgid\" -o \"$lowered\"");

  my $linked=$base.".linked.bc";
  # Link with the soft IP library 
  my $late_bc = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_late.bc");
  $return_status = mysystem_full(
      {'stdout' => $fulllog, 'title' => 'Late library'},
      "$link_exe \"$lowered\" $late_bc -o \"$linked\"" );

  my $final = $base.".bc";
  # Inline IP calls, simplify and clean up
  $return_status = mysystem_full(
      {'stdout' => $fulllog, 'title' => "Inline and clean up"},
      "$opt_exe -HLS $llvm_board_option $debug_option -always-inline -add-inline-tag -instcombine -adjust-sizes -dce -stripnk -area-print $opt_arg_after \"$linked\" -o \"$final\"");
  if ( $disassemble) { mysystem("llvm-dis \"$final\" " ) == 0 or mydie("Cannot disassemble: \"$final\" \n"); }

    

  if ( $ip_only ) { myexit("Intrinsics Step"); }
  
  my $design_area = undef;
  
  $return_status = mysystem_full(
      {'stdout' => $fulllog, 'title' => 'LLC'},
      "$llc_exe  -march=fpga -mattr=option3wrapper -fpga-const-cache=1 -HLS $llvm_board_option $debug_option $llc_arg_after \"$final\" -o \"$base.v\"");
  if ( $llc_only ) {  myexit("LLC Step"); }

  # Visualization support
  if ( $dash_g ) { # Need dwarf file list for this to wor
      my $files = `file-list \"$work_dir/$optinfile\"`;
      my $index = 0;
      foreach my $file ( split(/\n/, $files) ) {
	  save_pkg_section($pkg,'.acl.file.'.$index,$file);
	  $pkg->add_file('.acl.source.'. $index,$file)
	      or mydie("Can't save source into package file: $acl::Pkg::error\n");
	  $index = $index + 1;
      }
      save_pkg_section($pkg,'.acl.nfiles',$index);
  }

  # Save Memory Architecture View JSON file 
  if ( -e "mav.json" ) {
      $pkg->add_file('.acl.mav.json', "mav.json")
	  or mydie("Can't save mav.json into package file: $acl::Pkg::error\n");
  }
  # Save Area Report JSON file 
  if ( -e "area.json" ) {
      $pkg->add_file('.acl.area.json', "area.json")
	  or mydie("Can't save area.json into package file: $acl::Pkg::error\n");
  }
  # Move over the Optimization Report to the log file 
  if ( -e "opt.rpt" ) {
      append_to_log( "opt.rpt", $fulllog );
  }

  # If estimate >100% of block ram, rerun opt with lmem replication disabled
  # Don't back off like this if DSE is active.
  #DSE driver
  $design_area = acl::DSE::dse_driver(0, 0); 
  

  open LOG, ">report.out";
  printf(LOG "\n".
	 "+--------------------------------------------------------------------+\n".
	 "; Estimated Resource Usage Summary                                   ;\n".
	 "+----------------------------------------+---------------------------+\n".
	 "; Resource                               + Usage                     ;\n".
	 "+----------------------------------------+---------------------------+\n".
	 "; Logic utilization                      ; %4d\%                     ;\n".
	 "; Dedicated logic registers              ; %4d\%                     ;\n".
	 "; Memory blocks                          ; %4d\%                     ;\n".
	 "; DSP blocks                             ; %4d\%                     ;\n".
	 "+----------------------------------------+---------------------------;\n", 
	 $design_area->{util}, $design_area->{ffs}, $design_area->{rams}, $design_area->{dsps});
  close LOG;
  
  append_to_log ("report.out", $fulllog);

  my $xml_file = "$base.bc.xml";

  mysystem_full(
       {'stdout' => $fulllog, 'title' => "System Integration"},
       "$sysinteg_exe $sysinteg_arg_after --hls \"$xml_file\" " );

  unlink( $pkg_file_final ) if -f $pkg_file_final;
  rename( $pkg_file, $pkg_file_final )
      or mydie("Can't rename $pkg_file to $pkg_file_final: $!");
  if ( $verilog_gen_only ) { myexit("Verilog Gen Step aka -c"); }

  if ($RTL_flow) { myexit("RTL Only"); }
  
  # read the comma-separated list of components from a file
  my $component_list_filename="component_list.txt";
  my $COMPONENT_LIST_FILE;
  open (COMPONENT_LIST_FILE, "<$component_list_filename") or mydie "Couldn't open $component_list_filename for read!\n";
  my @component_list = <COMPONENT_LIST_FILE>;  # component names are listed in a comma-separated first line of the file
  close COMPONENT_LIST_FILE;
  hls_sim_generate_verilog($base, $component_list[0], $fulllog, $family, $work_dir);  

  return;

  $pkg->set_file('.acl.autodiscovery',"sys_description.txt")
    or mydie("Can't save system description into package file: $acl::Pkg::error\n");

  if(-f "autodiscovery.xml") {
    $pkg->set_file('.acl.autodiscovery.xml',"autodiscovery.xml")
      or mydie("Can't save system description xml into package file: $acl::Pkg::error\n");    
  } else {
     print "Could not find autodiscovery xml\n"
  }  

  my $board_xml = get_acl_board_hw_path($board_variant)."/$board_variant";

  if(-f $board_xml) {
    $pkg->set_file('.acl.board_spec.xml',$board_xml)
      or mydie("Can't save boardspec.xml into package file: $acl::Pkg::error\n");    
  }else {
     print "Could not find board spec xml\n"
  } 
  

  my $cmp_dir = $base; 

  # Move ip files generated by verilog generation (llc, system_integrator) to ip directory.
  acl::File::copy_tree( "${cmp_dir}.v", "ip/$cmp_dir/" )
    or mydie("Can't copy generated IP file ${cmp_dir}.v: $acl::File::error");
  acl::File::copy_tree( "${cmp_dir}_system.v", "ip/$cmp_dir" )
    or mydie("Can't copy generated system file ${cmp_dir}_system.v: $acl::File::error");
  acl::File::copy_tree( "${cmp_dir}_system_hw.tcl", "ip/$cmp_dir" )
    or mydie("Can't copy generated system file ${cmp_dir}_system_hw.tcl: $acl::File::error");
  
  unlink "${cmp_dir}_system.v";
  unlink "${cmp_dir}_system_hw.tcl";

  my $pkgo_file = $obj; # Should have been created by first phase.
  $pkg_file = $x_file.".tmp";
  $pkg_file_final = $x_file;

  acl::File::copy( $pkgo_file, $pkg_file )
   or mydie("Can't copy binary package file $pkgo_file to $pkg_file: $acl::File::error");
  $pkg = get acl::Pkg($pkg_file)
     or mydie("Can't find package file: $acl::Pkg::error\n");

  # Set version again, for informational purposes.
  # Do it again, because the second half flow is more authoritative
  # about the executable contents of the package file.
  save_pkg_section($pkg,'.acl.version',acl::Env::sdk_version());

  #Ignore SOPC Builder's return value
  my $sopc_builder_cmd = $ENV{QUARTUS_ROOTDIR}."/sopc_builder/bin/qsys-script";
  my $ip_gen_cmd = $ENV{QUARTUS_ROOTDIR}."/sopc_builder/bin/ip-generate";
  
  # Run Java Runtime Engine with max heap size 512MB, and serial garbage collection.
  my $jre_tweaks = "-Xmx512M -XX:+UseSerialGC";
  
  open LOG, "<sopc.tmp";
  while (<LOG>) { print if / Error:/; }
  close LOG;

  if (-e "base.qsf") 
  {
     print "$prog: Setting up project for CvP revision flow....\n" if $verbose;
     $return_status = mysystem_full(
        {'stdout' => $fulllog, 'title' => "Qsys-script kernel system" },
        "$sopc_builder_cmd --script=kernel_system.tcl $jre_tweaks 2>&1" );

     $return_status =mysystem_full(
	{'stdout' => $fulllog, 'title' => "Qsys-script system" },
        "$sopc_builder_cmd --script=system.tcl $jre_tweaks --system-file=system.qsys 2>&1" );
 } else {
     print "$prog: Setting up project for QXP preservation flow....\n" if $verbose;
     $return_status = mysystem_full(
        {'stdout' => $fulllog, title => "QXP preservation flow" },
        "$sopc_builder_cmd --script=system.tcl $jre_tweaks --system-file=system.qsys 2>&1" );
  }

  if ( $skip_qsys) { myexit("Qsys Step"); }

  $return_status = mysystem_full( 
      {'stdout' => $fulllog, 'title' => "IP-generate"},
      "$ip_gen_cmd --component-file=system.qsys --file-set=QUARTUS_SYNTH --output-directory=system/synthesis --report-file=qip:system/synthesis/system.qip --jvm-max-heap-size=3G 2>&1" );  

  # Some boards may post-process qsys output
  my $postqsys_script = acl::Env::board_post_qsys_script();
  if (defined $postqsys_script and $postqsys_script ne "") {
    mysystem( "$postqsys_script" ) == 0 or mydie("Couldn't run postqsys-script for the board!\n");
  }
  
  if ( $ip_gen_only ) { myexit("IP Generate Step"); }

  my @designs = acl::File::simple_glob( "*.qpf" );
  $#designs >= 0 or mydie ("Internal Compiler Error.\n");
  $#designs == 0 or mydie ("Internal Compiler Error.\n");
  my $design = shift @designs;
  

  $return_status = mysystem_full(
      {'stdout' => 'quartus_sh_compile.log', 'title' => "Quartus"},
      $ENV{QUARTUS_ROOTDIR}."/$qbindir/quartus_sh --flow compile $design");

  # check sta log for timing not met warnings
  print "$prog: Hardware generation completed successfully.\n" if $verbose;

  my $fpga_bin = 'fpga.bin';
  if ( -f $fpga_bin ) {
    $pkg->set_file('.acl.fpga.bin',$fpga_bin)
       or mydie("Can't save FPGA configuration file $fpga_bin into package file: $acl::Pkg::error\n");

  } else { #If fpga.bin not found, package up sof and core.rbf

    # Save the SOF in the package file.
    my @sofs = (acl::File::simple_glob( "*.sof" ));
    if ( $#sofs < 0 ) {
      print "$prog: Warning: Could not find a FPGA programming (.sof) file\n";
    } else {
      if ( $#sofs > 0 ) {
        print "$prog: Warning: Found ".(1+$#sofs)." FPGA programming files. Using the first: $sofs[0]\n";
      }
      $pkg->set_file('.acl.sof',$sofs[0])
        or mydie("Can't save FPGA programming file into package file: $acl::Pkg::error\n");
    }
    # Save the RBF in the package file, if it exists.
    # Sort by name instead of leaving it random.
    # Besides, sorting will pick foo.core.rbf over foo.periph.rbf
    foreach my $rbf_type ( qw( core periph ) ) {
      my @rbfs = sort { $a cmp $b } (acl::File::simple_glob( "*.$rbf_type.rbf" ));
      if ( $#rbfs < 0 ) {
        #     print "$prog: Warning: Could not find a FPGA core programming (.rbf) file\n";
      } else {
        if ( $#rbfs > 0 ) {
          print "$prog: Warning: Found ".(1+$#rbfs)." FPGA $rbf_type.rbf programming files. Using the first: $rbfs[0]\n";
        }
        $pkg->set_file(".acl.$rbf_type.rbf",$rbfs[0])
          or mydie("Can't save FPGA $rbf_type.rbf programming file into package file: $acl::Pkg::error\n");
      }
    }
  }

  my $pll_config = 'pll_config.bin';
  if ( -f $pll_config ) {
    $pkg->set_file('.acl.pll_config',$pll_config)
       or mydie("Can't save FPGA clocking configuration file $pll_config into package file: $acl::Pkg::error\n");
  }
  
  my $acl_quartus_report = 'acl_quartus_report.txt';
  if ( -f $acl_quartus_report ) {
    $pkg->set_file('.acl.quartus_report',$acl_quartus_report)
       or mydie("Can't save Quartus report file $acl_quartus_report into package file: $acl::Pkg::error\n");
  }

  unlink( $pkg_file_final ) if -f $pkg_file_final;
  rename( $pkg_file, $pkg_file_final )
    or mydie("Can't rename $pkg_file to $pkg_file_final: $!");

  chdir $orig_dir or mydie("Can't change back into directory $orig_dir: $!");
}

# List installed boards.
sub list_boards {
  print "Board list:\n";

  # We want to find $acl_board_path/*/*.xml, however acl::File::simple_glob
  # cannot handle the two-levels of wildcards. Do one at a time.
  my @boards = ();
  my $acl_board_path = acl::Board_env::get_board_path();
  $acl_board_path = "/";
  $acl_board_path .= acl::Board_env::get_hardware_dir();
  $acl_board_path = acl::File::abs_path($acl_board_path);
  my @board_dirs = acl::File::simple_glob($acl_board_path . "/*");
  foreach my $dir (@board_dirs) {
    my @board_spec = acl::File::simple_glob($dir . "/board_spec.xml");
    if(scalar(@board_spec) != 0) {
      my ($board) = ($dir =~ m!/([^/]+)$!);
      push(@boards, $board);
    }
  }

  if( $#boards == -1 ) {
    print "  none found\n";
  }
  else {
    print join('', map { "  $_\n" } sort @boards);
  }
}


sub usage() {
  print <<USAGE;

acc -- Altera SDK for HLS Compiler

Usage: acc <options> <kernel>.[cxx|cpp|c] 

Example:
       acc mycomponent.cpp

Outputs:
       <File>.exe (emulation)
       <File>.aoco and directory <File> (simulation/rtl generation)

Help Options:
--version
          Print out version infomation and exit

-v        
          Verbose mode. Report progress of compilation

-h
--help    
          Show this message

Overall Options:

-c
          Stops after generating verilog. There is currently no way to restart
          the compilation from this point.

-o <name>
          Renames emulation/simulation executable to <name>, project directory to <name> 
          and aoc file to <name>.aoco. All other names derived from the source 
          file name remain unchanged.

-march=emulator 
	  Generate a version of the testbench and components that can execute
	  locally on the host machine. Generated file is called <File>.exe.

--RTL-only
--rtl-only
          Stop after generating a verilog file.

-g        
          Add debug data. Needed by visualizer to view source. Makes it 
          possible to symbolically debug kernels created for the emulation 
          on an x86 machine (Linux only).

-I <directory> 
          Add directory to header search path.

-L <directory> 
          Add directory to library search path.

-l<library name> 
          Add library to to header search pathlink against.

-D <name> 
          Define macro, as name=value or just name.

-W        
          Supress warning.

-Werror   
          Make all warnings into errors.


Modifiers:
--family <device family name>
          Specifies the device family, the default is "Stratix V". 
          Supported device families: "Stratix V", "Cyclone V" and "Arria 10"

Optimization Control:
--fmax <Fmax>
          Instruct the compiler to optimize the circuit for a specific Fmax.
          The default Fmax target is 250 MHz. 


--fp-relaxed
          Allow the compiler to relax the order of arithmetic operations,
          possibly affecting the precision

--fpc 
          Removes intermediary roundings and conversions when possible, 
          and changes the rounding mode to round towards zero for 
          multiplies and adds

USAGE

}

sub version($) {
  my $outfile = $_[0];
  print $outfile "a++ (TM) 1.0.0\n";
  print $outfile "Altera++ Compiler, 64-Bit C++ based High Level Synthesis\n";
  print $outfile "Version 14.1 Build 180\n";
  print $outfile "Copyright (C) 2014 Altera Corporation\n";
}

sub main {
  my @args = (); # regular args.
  @user_opencl_args = ();
  my $atleastoneflag=0;
  my $dirbase=undef;
  my $board_variant=undef;
  my $family=undef;
  my $x_file=undef;
  while ( $#ARGV >= 0 ) {
    my $arg = shift @ARGV;
    if ( ($arg eq '-h') or ($arg eq '--help') ) { usage(); exit 0; }
    elsif ( ($arg eq '--version') or ($arg eq '-V') ) { version(\*STDOUT); exit 0; }
    elsif ( ($arg eq '-v') ) { $verbose += 1; if ($verbose > 1) {$prog = "#$prog";} }
    elsif ( ($arg eq '-d') ) { $debug_option = "-mllvm -debug";}
    elsif ( ($arg eq '-g') ) { $dash_g = 1;}
    elsif ( ($arg eq '-o') ) {
      # Absorb -o argument, and don't pass it down to Clang
      $#ARGV >= 0 or mydie("Option $arg requires a file argument.");
      $output_file = shift @ARGV;
    }
    elsif ($arg eq '--ggdb' || $arg eq '-march=emulator' ) {
      $emulator_flow = 1;
      if ($arg eq '--ggdb') {
	  push @args, '-g';
      }
    }
    elsif ($arg eq '-march=simulator' ) {
      $simulator_flow = 1;
    }
    elsif ($arg eq '--RTL-only' || $arg eq '--rtl-only' ) {
      $RTL_flow = 1;
    }
    elsif ($arg eq '--func') {
      $#ARGV >= 0 or mydie("Option --func requires a function name");
      $root_name = (shift @ARGV);
    }
    elsif ( ($arg eq '--clang-arg') ) {
      $#ARGV >= 0 or mydie("Option --clang-arg requires an argument");
      # Just push onto @args!
      push @args, shift @ARGV;
    }
    elsif ( ($arg eq '--opt-arg') ) {
      $#ARGV >= 0 or mydie("Option --opt-arg requires an argument");
      $opt_arg_after .= " ".(shift @ARGV);
    }
    elsif( ($arg eq '--one-pass') ) {
      $#ARGV >= 0 or mydie("Option --one-pass requires an argument");
      $opt_passes = " ".(shift @ARGV);
      $opt_only = 1;
    }
    elsif ( ($arg eq '--llc-arg') ) {
      $#ARGV >= 0 or mydie("Option --llc-arg requires an argument");
      $llc_arg_after .= " ".(shift @ARGV);
    }
    elsif ( ($arg eq '--optllc-arg') ) {
      $#ARGV >= 0 or mydie("Option --optllc-arg requires an argument");
      my $optllc_arg = (shift @ARGV);
      $opt_arg_after .= " ".$optllc_arg;
      $llc_arg_after .= " ".$optllc_arg;
    }
    elsif ( ($arg eq '--sysinteg-arg') ) {
      $#ARGV >= 0 or mydie("Option --sysinteg-arg requires an argument");
      $sysinteg_arg_after .= " ".(shift @ARGV);
    }
    elsif ( ($arg eq '--parse-only') ) { $parse_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--link-only') ) { $link_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--opt-only') ) { $opt_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--intrinsics-only') ) { $ip_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--llc-only') ) { $llc_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--v-only') ) { $verilog_gen_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--ip-only') ) { $ip_gen_only = 1; $atleastoneflag = 1; }

    elsif ( ($arg eq '-c') ) { $verilog_gen_only = 1; $atleastoneflag = 1; }

    elsif ( ($arg eq '--dump-csr') ) {
      $llc_arg_after .= ' -csr';
    }
    elsif ( ($arg eq '--dis') ) { $disassemble = 1; }    
    elsif ($arg eq '--family') {
      ($family) = (shift @ARGV);
    }
    elsif ($arg eq '--dot') {
      $dotfiles = 1;
    }
    elsif ( ($arg eq '--fmax') ) {
      $opt_arg_after .= ' -scheduler-fmax=';
      $llc_arg_after .= ' -scheduler-fmax=';
      my $fmax_constraint = (shift @ARGV);
      $opt_arg_after .= $fmax_constraint;
      $llc_arg_after .= $fmax_constraint;
    }
    elsif ( ($arg eq '--fp-relaxed') ) {
      $opt_arg_after .= " -fp-relaxed=true";
    }
    elsif ( ($arg eq '--fpc') ) {
      $opt_arg_after .= " -fpc=true";
    }

    elsif ($arg =~ /^-[lL]/) {
	push @user_linkflags, $arg;
    }
    elsif ( $arg =~ m/\.c$|\.cc$|\.cp$|\.cxx$|\.cpp$|\.CPP$|\.c\+\+$|\.C$/ ) {
      !defined $input_file or mydie("Too many input files provided: $input_file and $arg\n");
      $input_file=$arg;
    } else { push @args, $arg }
  }

  if ($dash_g) {
      push @args, '-g';
      $llc_arg_after.= ' -dbg-info-enabled';
  } 
  
  ### list of supported families
  my $SV_family = "Stratix V";
  my $CV_family = "Cyclone V";
  my $A10_family = "Arria 10";
  
  ### the associated reference boards
  my %family_to_board_map = (
        $SV_family  => 'SV.xml',
        $CV_family  => 'CV.xml',
        $A10_family => 'A10.xml'
  );
  my $supported_families_str;
  foreach my $key (keys %family_to_board_map) { $supported_families_str .= "\n\"$key\" " }

  # if no family specified, then use Stratix V family default board
  if (!defined $family) {
    $family = $SV_family;
    ($board_variant) = $family_to_board_map{$family};
  } else {
    if (!defined $family_to_board_map{$family}) {
      mydie("Unsupported device family: $family. \nSupported device families: $supported_families_str");
    } else {
      ($board_variant) = $family_to_board_map{$family};
    }          
  } 

  @user_clang_args = @args;
  push @user_opencl_args, @user_clang_args;

  if (defined $root_name) {
      $clang_arg_after = "-soft-ip-c-func-name=$root_name";
  }

  if ($dotfiles) {
    $opt_arg_after .= ' --dump-dot ';
    $llc_arg_after .= ' --dump-dot '; 
    $sysinteg_arg_after .= ' --dump-dot ';
  }

  $orig_dir = acl::File::abs_path('.');

  my $base = acl::File::mybasename($input_file);
  my $suffix = $base;
  $suffix =~ s/.*\.//;
  $base=~ s/\.$suffix//;
  $base =~ s/[^a-z0-9_]/_/ig;
  
  -f $input_file or mydie("Invalid kernel file $input_file: $!");
  $srcfile = $input_file;
  $objfile = $base.".aoco";
  $x_file = $base.".aocx";
  $dirbase = $base;
    
  if ( $output_file ) {
    my $outsuffix = $output_file;
    $outsuffix =~ s/.*\.//;
    my $outbase = $output_file;
    $outbase =~ s/\.$outsuffix//;
    $outbase =~ s/[^a-z0-9_]/_/ig;
    $objfile = $outbase.".aoco";
    $dirbase = $outbase;  # our first option is to use $outbase as $dirbase
    if  ($dirbase eq $output_file) {
      $dirbase .= '_rtl';  # but then append "_rtl" as fallback to $dirbase in the case when $output_file has no extension
    }
    $x_file = undef;

    $output_file = acl::File::abs_path( $output_file );
  }
  $objfile = acl::File::abs_path( $objfile );
  $x_file = acl::File::abs_path( $x_file );
  

  # Check that this is a valid board directory by checking for a board model .xml 
  # file in the board directory.
  if (not $emulator_flow) {
    my $board_xml = get_acl_board_hw_path($board_variant)."/$board_variant";
    if (!-f $board_xml) {
      mydie("Board '$board_variant' not found!\n");
    }
  }

  $work_dir = acl::File::abs_path("./$dirbase");

  compile ($base, $work_dir, $srcfile, $objfile, $x_file, $board_variant, $family);
}

sub hls_sim_generate_verilog($) {
  
  my ($HLS_FILENAME_NOEXT, $DUT_LIST, $fulllog, $family, $work_dir) = @_;

  # create an array from a comma-separated string
  my @dut_array = split(/,/, $DUT_LIST);  
  # then ensure that each component is listed only once in the list, i.e., remove duplicates from the component array
  my %seen;
  @dut_array = grep { ! $seen{ $_ }++ } @dut_array;
  # finally, recreate the comma-separated string from the array with unique elements
  $DUT_LIST  = join(',',@dut_array);

  print "Generating simulation files for components: $DUT_LIST\n";

  if (!defined($HLS_FILENAME_NOEXT) or !defined($DUT_LIST)) {
    mydie("Error: Pass the input file name and component names into the hls_sim_generate_verilog function\n");
  }

  my $HLS_GEN_FILES_DIR = $HLS_FILENAME_NOEXT;
  my $SEARCH_PATH = acl::Env::sdk_root()."/ip/src/common/,\$,".$HLS_GEN_FILES_DIR; # no space between paths!

  # Setup file path names
  my $HLS_GEN_FILES_SIM_DIR = "./sim";
  my $HLS_QSYS_SIM_NOEXT    = $HLS_FILENAME_NOEXT."_sim";

  # Because the qsys-script tcl cannot accept arguments, 
  # pass them in using the --cmd option, which runs a tcl cmd
  my $init_var_tcl_cmd = "set sim_qsys $HLS_FILENAME_NOEXT; set component_list $DUT_LIST;";

  # Create the simulation directory  
  my $sim_dir_abs_path = acl::File::abs_path("./$HLS_GEN_FILES_SIM_DIR");
  print "HLS simulation directory: $sim_dir_abs_path.\n";
  acl::File::make_path($HLS_GEN_FILES_SIM_DIR) or mydie("Can't create simulation directory $sim_dir_abs_path: $!");

  my $gen_qsys_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_sim_generate_qsys.tcl";

  # Run hls_sim_generate_qsys.tcl to generate the .qsys file for the simulation system 
  $return_status = mysystem_full({'stdout' => $fulllog, , 'stderr' => $fulllog, 'title' => 'gen_qsys'},'qsys-script --search-path='.$SEARCH_PATH.' --script='.$gen_qsys_tcl.' --cmd="'.$init_var_tcl_cmd.'"');

  # Move the .qsys we just made to the sim dir
  $return_status = mysystem_full({'stdout' => $fulllog, , 'stderr' => $fulllog, 'title' => 'move qsys'},"mv $HLS_QSYS_SIM_NOEXT.qsys $HLS_GEN_FILES_SIM_DIR");

  # Generate the verilog for the simulation system
  $return_status = mysystem_full({'stdout' => $fulllog, 'stderr' => $fulllog, 'title' => 'generate verilog'},"ip-generate --search-path=$SEARCH_PATH --component-file=$HLS_GEN_FILES_SIM_DIR/$HLS_QSYS_SIM_NOEXT.qsys --report-file=spd:$HLS_GEN_FILES_SIM_DIR/$HLS_QSYS_SIM_NOEXT.spd --output-name=$HLS_QSYS_SIM_NOEXT --file-set=SIM_VERILOG --output-directory=$HLS_GEN_FILES_SIM_DIR --system-info=DEVICE_FAMILY=\"$family\"");

  # Generate simulation scripts
  $return_status = mysystem_full({'stdout' => $fulllog, 'stderr' => $fulllog, 'title' => 'generate simulation script'},
			    "ip-make-simscript --compile-to-work -spd=$HLS_GEN_FILES_SIM_DIR/$HLS_QSYS_SIM_NOEXT.spd --output-directory=$HLS_GEN_FILES_SIM_DIR");

  # Finally, generate scripts that the user can run to perform the actual simulation.
  generate_simulation_scripts($HLS_FILENAME_NOEXT, $HLS_GEN_FILES_SIM_DIR, $work_dir);
}


# This module creates 3 files:
#  - <source>_compile.do      (the script run by the compilation phase, in the output dir)
#  - <source>_simulate.do     (the script run by the simulation phase, in the output dir)
#  - <source>_sim.pl          (the top-level simulation script, in the output dir)
#  - <source>_sim             (the executable top-level simulation script, in the top-level dir)
sub generate_simulation_scripts($) {

  my ($HLS_QSYS_SIM_NOEXT, $HLS_GEN_FILES_SIM_DIR, $work_dir) = @_;

  # ----------------------------------------------------------------------------
  # First, create the .do for the system compilation
  # ----------------------------------------------------------------------------
  
  # Put the required commands in <source>_compile.do
  my $com_do = "${HLS_QSYS_SIM_NOEXT}_compile.do";
  open(my $com_file, '>', $com_do) or die "Could not open file '$com_do' $!";
  print $com_file "set QSYS_SIMDIR $HLS_GEN_FILES_SIM_DIR;\n";
  # Source msim_setup.tcl to link the required files. 
  my $msim_setup_dir = "$HLS_GEN_FILES_SIM_DIR/mentor/msim_setup.tcl";
  print $com_file "source $msim_setup_dir;\n";
  # Compilation commands
  print $com_file "dev_com;\n";
  print $com_file "com;\n";
  print $com_file "exit;\n";
  close $com_file;
  
  # ----------------------------------------------------------------------------
  # Next, create the .do for the system simulation
  # ----------------------------------------------------------------------------
  my $sim_time=undef;

  # Put the required commands in <system>_simulation.do 
  my $sim_do = "${HLS_QSYS_SIM_NOEXT}_simulate.do";
  open(my $sim_file, '>', $sim_do) or die "Could not open file '$sim_do' $!";
  # Source msim_setup.tcl to link the required libraries. 
  print $sim_file "source $msim_setup_dir;\n";
  # Set elaboration options, including the DPI library directory
  # my $DPI_LIBDIR=".";
  print $sim_file 'set ELAB_OPTIONS "+nowarnTFMPC -dpioutoftheblue 1 -sv_lib '.$HLS_QSYS_SIM_NOEXT.'_sim";'."\n"; ##-quiet
  # Call the elaboration within the auto-generated modelsim script.
  print $sim_file "elab_debug;\n";
  # Any custom additional commands
  print $sim_file "log -r /*;\n";
  # Command to actually run the simulation
  if ($sim_time) {
    print $sim_file "run $sim_time;\n";
  } else {
    print $sim_file "run 100ms;\n";
  }
  print $sim_file "exit;\n";
  close $sim_file;

  # ----------------------------------------------------------------------------
  # Create the .pl script that compiles and run simulation
  # ----------------------------------------------------------------------------
  my $sim_pl = "${HLS_QSYS_SIM_NOEXT}_sim.pl";
  open(my $pl_script, '>', $sim_pl) or die "Could not open file '$sim_pl' $!";
  print $pl_script 'system("vsim -c -do '.$com_do.'");
system("vsim -c -do '.$sim_do.'");
';
  close $pl_script;

  # ----------------------------------------------------------------------------
  # Also create an executable script in the top dir (does the same as perl script)
  # ----------------------------------------------------------------------------
  # This will also need a Windows version once cosim for Windows is enabled

  my $sim_exe_fname;
  if (defined($output_file)) {
    $sim_exe_fname = $output_file;
  } else {
    $sim_exe_fname = "../${HLS_QSYS_SIM_NOEXT}_sim";
  }
  open(my $sim_exe, '>', $sim_exe_fname) or die "Could not open file '$sim_exe_fname' $!";
  print $sim_exe '#!/bin/sh
curr_dir=`pwd`
cd '.$work_dir.'
vsim -c -do '.$com_do.'
vsim -c -do '.$sim_do.'
cd $curr_dir
';
  close $sim_exe;
  system("chmod +x ".$sim_exe_fname); 
  
}

main();
exit 0;
