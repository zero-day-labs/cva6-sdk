REPETITIONS=12

cd /mibench/automotive/qsort
echo qsort-small
perf stat --table -n -r $REPETITIONS ./runme_small.sh

echo qsort-large
perf stat --table -n -r $REPETITIONS ./runme_large.sh


cd /mibench/automotive/susan
echo susanc-small
perf stat --table -n -r $REPETITIONS ./runme_small-c.sh

echo susanc-large
perf stat --table -n -r $REPETITIONS ./runme_large-c.sh

echo susane-small
perf stat --table -n -r $REPETITIONS ./runme_small-e.sh

echo susane-large
perf stat --table -n -r $REPETITIONS ./runme_large-e.sh

echo susans-small
perf stat --table -n -r $REPETITIONS ./runme_small-s.sh

echo susans-large
perf stat --table -n -r $REPETITIONS ./runme_large-s.sh


cd /mibench/automotive/bitcount
echo bitcount-small
perf stat --table -n -r $REPETITIONS ./runme_small.sh

echo bitcount-large
perf stat --table -n -r $REPETITIONS ./runme_large.sh


cd /mibench/automotive/basicmath
echo basicmath-small
perf stat --table -n -r $REPETITIONS ./runme_small.sh

echo basicmath-large
perf stat --table -n -r $REPETITIONS ./runme_large.sh


cd /