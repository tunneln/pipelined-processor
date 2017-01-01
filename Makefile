VFILES=$(wildcard *.v)

OK = $(sort $(wildcard *.ok))
TESTS = $(patsubst %.ok,%,$(OK))
RAWS = $(patsubst %.ok,%.raw,$(OK))
VCDS = $(patsubst %.ok,%.vcd,$(OK))
OUTS = $(patsubst %.ok,%.out,$(OK))
CYCLES = $(patsubst %.ok,%.cycle,$(OK))
RESULTS = $(patsubst %.ok,%.result,$(OK))

cpu : $(VFILES) Makefile
	iverilog -o cpu $(VFILES)

test : $(RESULTS)

clean :
	rm -rf cpu *.out *.vcd *.raw *.cycle mem.hex

$(RAWS) : %.raw : Makefile cpu %.hex
	cp $*.hex mem.hex
	timeout 10 ./cpu > $*.raw 2>&1
	mv cpu.vcd $*.vcd

$(VCDS) : %.vcd : %.raw;

$(OUTS) : %.out : Makefile %.raw
	egrep "^#" $*.raw > $*.out

$(CYCLES) : %.cycle : Makefile %.raw
	egrep "^@" $*.raw > $*.cycle

$(RESULTS) : %.result : Makefile %.out %.cycle %.ok
	@echo -n "$* ... "
	@((diff -wbB $*.out $*.ok > /dev/null 2>&1) && echo "pass `cat $*.cycle`") || (echo "fail" ; echo "\n\n----------- expected ----------"; cat $*.ok ; echo "\n\n------------- found ----------"; cat $*.out)
