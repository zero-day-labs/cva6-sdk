REPETITIONS=$1
FILE=$2
if [ X$FILE = X ]
then	FILE=/tmp/XXX
	touch $FILE || echo Can not create $FILE >> ${OUTPUT}
fi
BW_N=100 #bw_mem repetitions
BW_W=10 #bw_mem warmups
#bw_mem
echo bw_mem
#Initialize bw_mem scenarios size 4K, 16K, 32K, 1MB, 2MB
bw_scenarios='4k 16k 32k 1m'

#Initialize bw_mem tests
#rd - measures the time to read data into the processor.
#wr - measures  the  time  to  write data to memory.
#rdwr - measures the time to read data into memory and then write data to the  same  memory location
#cp - measures  the  time  to  copy  data from one location to another.
#fwr - measures the time to read data into the processor.
#frd - measures  the  time  to  write data to memory.
#fcp - measures the time to copy data from one location to  another.
#bzero - measures how fast the system can bzero memory.
#bcopy - measures how fast the system can bcopy data.
i=0
bw_tests='rd wr rdwr cp fwr frd fcp bzero bcopy'
for scenario in $bw_scenarios; do
    echo "$scenario reps: $REPETITIONS"
    for test in $bw_tests; do
        echo $test
        i=0
        while [ $i -ne $REPETITIONS ]; do
            i=$(($i+1))
            bw_mem -W $BW_W -N $BW_N $scenario $test
        done
    done
done

lmdd label="File $FILE write bandwidth: " of=$FILE move=8m fsync=1 print=3
#bw_file_rd
echo bw_file_rd
touch $FILE
for scenario in $bw_scenarios; do
    echo "$scenario reps: $REPETITIONS"
    echo open2close
    i=0
    while [ $i -ne $REPETITIONS ]; do
        i=$(($i+1))
        bw_file_rd -W $BW_W -N $BW_N $scenario open2close $FILE
    done
done
for scenario in $bw_scenarios; do
    echo "$scenario reps: $REPETITIONS"
    echo io_only
    i=0
    while [ $i -ne $REPETITIONS ]; do
        i=$(($i+1))
        bw_file_rd -W $BW_W -N $BW_N $scenario io_only $FILE
    done
done
#bw_mmap_rd
echo bw_mmap_rd
for scenario in $bw_scenarios; do
    echo "$scenario reps: $REPETITIONS"
    echo open2close
    i=0
    while [ $i -ne $REPETITIONS ]; do
        i=$(($i+1))
        bw_mmap_rd -W $BW_W -N $BW_N $scenario open2close $FILE
    done
done
for scenario in $bw_scenarios; do
    echo "$scenario reps: $REPETITIONS"
    echo mmap_only
    i=0
    while [ $i -ne $REPETITIONS ]; do
        i=$(($i+1))
        bw_mmap_rd -W $BW_W -N $BW_N $scenario mmap_only $FILE
    done
done
rm -f $FILE
#lat_ctx
echo lat_ctx
msleep 250
CTX="0 4 8 16 32 64"
N="2 4 8 16 24 32 64 96"
for size in $CTX
do	
	lat_ctx -s $size $N
done
#lat_mmap
echo lat_mmap
i=0
lmdd label="File $FILE write bandwidth: " of=$FILE move=8m fsync=1 print=3
for scenario in $bw_scenarios; do
    echo "$scenario reps: $REPETITIONS"
    i=0
    while [ $i -ne $REPETITIONS ]; do
        i=$(($i+1))
        lat_mmap -W $BW_W -N $BW_N $scenario $FILE
    done
done
rm -f $FILE
lmdd label="File $FILE write bandwidth: " of=$FILE move=8m fsync=1 print=3
#lat_lat_pagefault
echo lat_pagefault
i=0
echo "reps: $REPETITIONS"
while [ $i -ne $REPETITIONS ]; do
     i=$(($i+1))
    lat_pagefault -W $BW_W -N $BW_N $FILE
done
rm -f $FILE
#lat_mem_read becrashou o sistema 
echo lat_mem_rd
i=0
lat_mem_rd_arr_size='16k 128k'
lat_mem_strides='64'
echo "Memory load latency"
for scenario in $lat_mem_rd_arr_size; do
    echo "$scenario reps: $REPETITIONS"
    i=0
    while [ $i -ne $REPETITIONS ]; do
        i=$(($i+1))
        lat_mem_rd -W $BW_W -N $BW_N $scenario 64
    done
done
echo "Random load latency"
i=0
for scenario in $lat_mem_rd_arr_size; do
    echo "$scenario reps: $REPETITIONS"
    i=0
    while [ $i -ne $REPETITIONS ]; do
        i=$(($i+1))
        lat_mem_rd -t -W $BW_W -N $BW_N $scenario 64
    done
done
#lat_ops benchmark
echo lat_ops
i=0
while [ $i -ne $REPETITIONS ]; do
    i=$(($i+1))
    lat_ops
done
