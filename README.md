# Build Rosetta on Hisilicon ARM aarch64 
By Yinying Yao



## Distinguish x86 and arm arch in the env file
This step is assuming your HPC provider have both login entrypoints to each arch using just one account.

Inspect processor's arch in `.bashrc` or `.bashrc.pre-oh-my-bash` when loging in
```shell
envfile_arm=/home/$(whoami)/.yyyrc.arm
envfile_x86=/home/$(whoami)/.yyyrc


# Automatically switch environment file by reading `uname -a`
if [[ "$(uname -a)" =~ "aarch64" ]];
then
    # we are ready in arm
    source $envfile_arm
else
    # in x86_64
    source $envfile_x86
fi
```


## Fetch Rosetta, latest weekly release

Fetch the tarred source code and un-tar it

### Be aware of x86 compilation
**It is recommended to build an x86 version of binaries firstly, then rename the `bin` dir as `bin_x86` or somewhat, so that the rest part of rosetta dir can be shared within both arch.**


```shell
# Non-MPI in x86
pushd /path-to/rosetta/release-version/source/
./scons.py -j 20  mode=release bin 

# MPI enable in x86
./scons.py -j 20  mode=release bin extras=mpi

# Rename compiled bin dir
mv ./bin ./bin_x86

# Create a new one
mkdir  bin

popd
```


## Pre-building setup 
There's a few setup steps to the compiler, Rosetta Scons, external software of Rosetta, required libraries and system variable 
paths.

_OpenMPI is optional but recommended._

### Bisheng LLVM Clang Setting
Download Bisheng LLVM Clang prebuilt binary package and install it.
```shell
export COMPRESSED=/path-to/compressed/
export ARM_BIN=/path-to/software_arm/bin/
wget https://mirrors.huaweicloud.com/kunpeng/archive/compiler/bisheng_compiler/bisheng-compiler-2.1.0-aarch64-linux.tar.gz -P $COMPRESSED

mkdir -P $ARM_BIN/bisheng
pushd $ARM_BIN/bisheng

tar xf /path-to/compressed/bisheng-compiler-2.1.0-aarch64-linux.tar.gz 

cd bisheng-compiler-2.1.0-aarch64-linux


echo "# Bisheng LLVM clang " >>$envfile_arm 
echo export PATH=$PWD/bin:'$PATH' >>$envfile_arm 
echo export CPATH=$PWD/include:'$CPATH' >>$envfile_arm
echo export LD_LIBRARY_PATH=$PWD/lib:'$LD_LIBRARY_PATH' >>$envfile_arm

popd
```


### (Optional)OpenMPI Setting (clang)

Here we build a copy of OpenMPI via Bisheng Clang

```shell
# fetch a copy of OpenMPI src and flatten it followed by building and installation
wget https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-4.1.2.tar.bz2 -P /path-to/compressed
cd /path-to/build/
tar xf /path-to/compressed/openmpi-4.1.2.tar.bz2
nohup bash /path-to-script/build_it_for_public.sh openmpi 4.1.2_w_fortran "--enable-mpi1-compatibility  FC=gfortran FCFLAGS='-fPIC -O0'  F77=gfortran FFLAGS='-fPIC -O0' F90=gfortran CC=clang CFLAGS='-fPIC' CXX=clang++" >~/logs/build_openmpi_w_fortran.log
```
Add to PATH and LD_LIBRARY_PATH.
After the building via the script, the PATH will be added to `$envfile_arm` automatically.



### Rosetta SCons System Setting
Setup for Hisilicon aarch64 chips w/ Bisheng Clang

#### 1. Adding self-defined site setting file
```shell
# Non-mpi, Bisheng LLVM clang
cd /path-to/rosetta/release-version/main/source
cp /path-to/scripts/site.settings.Hisilicon_aarch64 tools/build/site.settings

# w/ OpenMPI built via Bisheng LLVM clang
cp /path-to/scripts/site.settings.Hisilicon_aarch64_mpi tools/build/site.settings
```


#### 2. Setup processor architecture and Bisheng clang version inspection

Here we add a basic option to let SCons know the new arch.
check [this file](./building_scripts/options.settings)
`rosetta/source/tools/build/options.settings:33`
```python
    "arch" : {
        "x86"     : [ "32", "64", "*" ],
        # XXX: It's not clear if "amd" is a meaningful category
        "amd"     : [ "32", "64", "*" ],
        "ppc"     : [ "32", "64", "*" ],
        "ppc64"     : [ "64" ],
        "arm" : ["64", "*"],
        "aarch64":["64"],  # Added by Yinying for aarch64
        "power4"  : [ "32", "64", "*" ],
        "*"       : [ "*" ],
    },
```
Setup processor alias so the building scripts will know the arch name.

check [this file](./building_scripts/setup_platforms.py)
`rosetta/source/tools/build/setup_platforms.py:163`
```python
    processor_translation = {
        # Results from platform.processor()
        "i386": "x86",
        "i486": "x86",
        "i586": "x86",
        "i686" : "x86",
        "x86_64" : "x86",
        "ppc64" : "ppc64",
        "powerpc" : "ppc",
        "aarch64": "aarch64", # Added by Yinying for aarch64 testing
        # Results from os.uname()['machine']
        # This isn't strictly true.  But we are not currently distinguishing
        # between AMD and Intel processors.
        "athlon" : "x86",
        "Power Macintosh" : "ppc",

	# Some architectures for Gentoo Linux -- should be handled by the processor.machine() fallback
	#"Intel(R) Core(TM)2 CPU T7400 @ 2.16GHz" : "x86",
	#'Intel(R) Xeon(TM) CPU 3.00GHz' : "x86",
	#'Intel(R) Core(TM) i7 CPU Q 720 @ 1.60GHz' : "x86",
    }
```
 Next, we setup processor data size 

`rosetta/source/tools/build/setup_platforms.py:210`
```python
    print(f"fetch actual_size={actual}")
    actual = {
        "32bit" : "32",
        "64bit" : "64",
        "aarch64": "64", # Added by Yinying for aarch64 testing
        # XXX: We are guessing here.  This may prove incorrect
        "i386" : "32",
        "i486" : "32",
        "i586" : "32",
        "i686" : "32",
        # XXX: What do 64 bit Macs show?
        "Power Macintosh" : "32",
    }.get(actual, "<unknown>")
```
Also, setup Bisheng LLVM clang toolkit for version inspection.

`rosetta/source/tools/build/setup_platforms.py:327`
```python
        if compiler_output:
            compiler_output_split=compiler_output.split()
            if compiler_output_split[0]=="HUAWEI" and compiler=='clang' \
                    and compiler_output_split[1]=='BiSheng' and compiler_output_split[5]=='version':
                print(f'BiSheng is detected.')
                full_version=compiler_output_split[6]
                version = ".".join(full_version.split(".")[0:2])
                return version, full_version
            full_version=compiler_output_split[2]
            if full_version == 'version' and compiler == 'clang':
                full_version = compiler_output_split[3]
            version = ".".join(full_version.split(".")[0:2])
```
### Rosetta External Software Modification
`source/external/libxml2/config.h`

comment this line (risky, untested, but helpful to prevent error throwing out during compilation)

```cpp
//#define VA_LIST_IS_ARRAY 1`.
```


## Build & Run 
```shell
pushd /path-to/rosetta/release-version/main/source;
./scons.py -j 20  mode=release cxx=clang bin extras=mpi;
popd
```


## Add Rosetta to PATH

```shell
cd <rosetta-path>
export ROSETTA=$PWD;
echo "export ROSETTA=$ROSETTA" >>$envfile_arm
echo 'export ROSETTA3_DB=$ROSETTA/main/database
export ROSETTA_BIN=$ROSETTA/main/source/bin
export ROSETTA3=$ROSETTA/main/source
export ROSETTA_PYTHON_SCRIPTS=$ROSETTA/main/source/scripts/python/public

export PATH=$PATH:$ROSETTA_BIN:$ROSETTA_PYTHON_SCRIPTS
export PYTHONPATH=$ROSETTA/main/source/scripts/python/public
export LD_LIBRARY_PATH=$ROSETTA/main/source/bin:$LD_LIBRARY_PATH ' >>$envfile_arm 

# added x86 bin dir to x86 env file
echo "export ROSETTA=$ROSETTA" >> $envfile_x86
echo 'export ROSETTA3_DB=$ROSETTA/main/database
export ROSETTA_BIN=$ROSETTA/main/source/bin_x86
export ROSETTA3=$ROSETTA/main/source
export ROSETTA_PYTHON_SCRIPTS=$ROSETTA/main/source/scripts/python/public

export PATH=$PATH:$ROSETTA_BIN:$ROSETTA_PYTHON_SCRIPTS
export PYTHONPATH=$ROSETTA/main/source/scripts/python/public
export LD_LIBRARY_PATH=$ROSETTA/main/source/bin:$LD_LIBRARY_PATH ' >>~/.yyyrc
```


## Useful links
 - [Rosetta Unit Tests](https://www.rosettacommons.org/docs/latest/development_documentation/test/run-unit-test)
 - [Bisheng LLVM Clang Compiler (Chinese,PDF)](https://support.huaweicloud.com/ug-bisheng-kunpengdevps/ug-bisheng-kunpengdevps.pdf)
 - [Q&A about Rosetta on aarch64 - Rosetta Forum](https://www.rosettacommons.org/node/11422)
 - [Rosetta building w/ OpenMPI and Clang (Chinese)](https://zhuanlan.zhihu.com/p/58384830)
