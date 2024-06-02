#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (C) 2019 FORTH-ICS/CARV
#		Panagiotis Peristerakis <perister@ics.forth.gr>
#

HALF_FREQ=$(shell expr $(TARGET_FREQ) / 2)

ifndef TARGET_FREQ
  $(error TARGET_FREQ not set - please export TARGET FREQ in Hz)
endif

ifndef NUM_HARTS
  $(error NUM_HARTS not set - please export number of harts)
endif

ifeq ($(shell expr $(TARGET_FREQ) \>= 50000000), 1)
  TARGET_BAUDRATE := 115200
else ifeq ($(shell expr $(TARGET_FREQ) \>= 40000000), 1)
	TARGET_BAUDRATE := 38400
else
	TARGET_BAUDRATE := 9600
endif

FILE_PATH = $(PLAT)

ifeq ($(MINIMAL),y)
	FILE_PATH = $(PLAT)-minimal
endif

clean:
	rm -f $(PLAT).dts $(PLAT)-minimal.dts
	rm -f ./bins/*

dts: clean
	cp $(PLAT)-template.dts $(FILE_PATH).dts
	python3 dts_gen.py $(FILE_PATH).dts $(NUM_HARTS) $(TARGET_FREQ) $(HALF_FREQ) $(TARGET_BAUDRATE) $(MINIMAL) $(IRQC) $(PLAT)

PHONY: clean.dts alsaqr.dts
