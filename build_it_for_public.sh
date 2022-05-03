#!/usr/bin/env bash
set -e

# quick example for native compilation
# cd build; tar xv ../compressed/gcc-4.8.5.tar.gz; cd gcc-4.8.5
# bash /path/to/scripts/build_it_for_public.sh gcc 4.8.5 "--enable-bootstrap --enable-shared --enable-threads=posix --enable-checking=release --with-system-zlib --enable-__cxa_atexit --disable-libunwind-exceptions --enable-gnu-unique-object --enable-linker-build-id --with-linker-hash-style=gnu --enable-languages=c,c++,obj-c++,fortran,go --enable-plugin --enable-initfini-array --disable-libgcj --enable-gnu-indirect-function CFLAGS='-L/path/to/software/setup/glibc/2.19/lib/libc.so.6' --disable-multilib"

usage(){
    echo "Usage:"
    echo "cd <program_src_dir>"
    echo 'bash /path/to/scripts/build_it_for_public.sh program_name program_version [other building option passed to entrypoint]'
    echo ""
    echo "Quick example:"
    echo 'cd build; tar xv ../compressed/gcc-4.8.5.tar.gz; cd gcc-4.8.5'
    echo 'bash /path/to/scripts/build_it_for_public.sh gcc 4.8.5 "--enable-bootstrap --enable-shared --enable-threads=posix --enable-checking=release --with-system-zlib --enable-__cxa_atexit --disable-libunwind-exceptions --enable-gnu-unique-object --enable-linker-build-id --with-linker-hash-style=gnu --enable-languages=c,c++,obj-c++,fortran,go --enable-plugin --enable-initfini-array --disable-libgcj --enable-gnu-indirect-function CFLAGS="-L/path/to/software/setup/glibc/2.19/lib/libc.so.6" --disable-multilib'
    exit 1
}
# User specific aliases and functions
strA=$(hostname)
if [[ $strA =~ "arm" ]]; then
    # we are ready in arm
    env_file=/home/$(whoami)/.yyyrc.arm
    setup_dir=/path/to/software_arm/
# add more elif blocks if more machines are included.
#elif [[ $strA == "blablabla" ]]; then
#    env_file=/mnt/data/envs/.jpasrc
#    setup_dir=/software/
else
    # in x86_64
    env_file=/home/$(whoami)/.yyyrc
    setup_dir=/path/to/software/
fi



# use half of processor number for making
# sorry guys ;-)
NPROC=$(echo "$(nproc)"/2 | bc)

# check env file
if [[ ! -f $env_file ]]; then
    echo $env_file does not exist!
    usage
fi

source $env_file

software=$1
version=$2
other_stuff=$3

# check input args
if [[ $software == "" || $version == "" ]]; then
    echo required input is missing!
    echo software: $software
    echo version: $version
    exit 1
fi

public_dir=$setup_dir
dst_dir=$software/$version/

# dirs and cleaning
mkdir -p $public_dir/$dst_dir || echo NEVER MIND
make distclean || echo NEVER MIND
make clean || echo NEVER MIND

mkdir build || echo NEVER MIND
cd build
make distclean || echo NEVER MIND
make clean || echo NEVER MIND

# find setup entrypoint
for exec in bootstrap Configure configure; do
    if [[ -f ../${exec} ]]; then
        echo Find $exec
        break
    fi
done

if [[ $exec == "" ]]; then
    echo configure entrypoint does not exist!
    exit 1
fi

#clear LD_LIBRARY_PATH for glibc as required.
if [[ $software == "glibc" ]]; then
    export LD_LIBRARY_PATH=""
fi

# building command
cmd="../$exec --prefix=$public_dir/$dst_dir  $other_stuff"
echo "$cmd"
eval "$cmd"

make -j$NPROC
make install

pushd $public_dir/$dst_dir

# setup envs
if [[ $software =~ "glibc" ]]; then
    echo Adding $software to PATH and LD_LIBRARY_PATH may be dangerous! Skipping ...
    exit 0
else
    echo -e "\n" >>$env_file
    echo "# $software $version, shared" >>$env_file
    if [[ -d $public_dir/$dst_dir/bin ]]; then
        echo Adding $public_dir/$dst_dir/bin to PATH
        echo export PATH=$PWD/bin:'$PATH' >>$env_file
    fi

    if [[ -d $public_dir/$dst_dir/include ]]; then
        echo Adding $public_dir/$dst_dir/include to CPATH
        echo export CPATH=$PWD/include:'$CPATH' >>$env_file
    fi

    if [[ -d $public_dir/$dst_dir/lib ]]; then
        echo Adding $public_dir/$dst_dir/lib to LD_LIBRARY_PATH
        echo export LD_LIBRARY_PATH=$PWD/lib:'$LD_LIBRARY_PATH' >>$env_file
    fi

    if [[ -d $public_dir/$dst_dir/lib64 ]]; then
        echo Adding $public_dir/$dst_dir/lib64 to LD_LIBRARY_PATH
        echo export LD_LIBRARY_PATH=$PWD/lib64:'$LD_LIBRARY_PATH' >>$env_file
    fi
fi

popd

