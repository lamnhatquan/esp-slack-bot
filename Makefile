
ESPTOOL 			?= /tools/esp8266/esptool/esptool.py
XTENSA_DIR 		?= /tools/esp8266/esp-open-sdk/xtensa-lx106-elf/bin
ESPPORT 			?= /dev/tty.SLAB_USBtoUART
SDK_BASE			?= /tools/esp8266/sdk/esp_iot_sdk_v1.5.2
SPI_SIZE_MAP	?= 6



THISDIR:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))

BUILD_BASE	= build
FW_BASE = firmware
TARGET = esp-slack-bot

DATETIME := `/bin/date "+%Y-%m-%d_%H:%M:%S"`

#############################################################
# Select compile
#
ifeq ($(OS),Windows_NT)
# WIN32
# We are under windows.
	ifeq ($(XTENSA_CORE),lx106)
		# It is xcc
		XTENSA_PREFIX = $(XTENSA_DIR)/xtensa-lx106-elf

	else
		# It is gcc, may be cygwin
		# Can we use -fdata-sections?
		CCFLAGS += -Os -ffunction-sections -fno-jump-tables
		XTENSA_PREFIX = $(XTENSA_DIR)/xtensa-lx106-elf
	endif

    ifeq ($(PROCESSOR_ARCHITECTURE),AMD64)
# ->AMD64
    endif
    ifeq ($(PROCESSOR_ARCHITECTURE),x86)
# ->IA32
    endif
else
# We are under other system, may be Linux. Assume using gcc.
	# Can we use -fdata-sections?


	CCFLAGS += -Os -ffunction-sections -fno-jump-tables
	XTENSA_PREFIX = $(XTENSA_DIR)/xtensa-lx106-elf

    UNAME_S := $(shell uname -s)

    ifeq ($(UNAME_S),Linux)
# LINUX
    endif
    ifeq ($(UNAME_S),Darwin)
# OSX
    endif
    UNAME_P := $(shell uname -p)
    ifeq ($(UNAME_P),x86_64)
# ->AMD64
    endif
    ifneq ($(filter %86,$(UNAME_P)),)
# ->IA32
    endif
    ifneq ($(filter arm%,$(UNAME_P)),)
# ->ARM
    endif
endif

AR = $(XTENSA_PREFIX)-ar
CC = $(XTENSA_PREFIX)-gcc
LD = $(XTENSA_PREFIX)-gcc
NM = $(XTENSA_PREFIX)-nm
CPP = $(XTENSA_PREFIX)-cpp
OBJCOPY = $(XTENSA_PREFIX)-objcopy

#############################################################


LDDIR = $(SDK_BASE)/ld
LD_FILE = $(LDDIR)/eagle.app.v6.ld
BIN_NAME = $(TARGET)
# linker script used for the above linkier step
LD_SCRIPT	= -T $(LD_FILE)
FLAVOR ?= release



# which modules (subdirectories) of the project to include in compiling
MODULES		= driver user

EXTRA_INCDIR    = include
EXTRA_LIBDIR = lib
EXTRA_LIBS =

# various paths from the SDK used in this project
SDK_LIBDIR	= lib
SDK_LDDIR	= ld
SDK_INCDIR	= include include/json




# libraries used in this project, mainly provided by the SDK
LIBS		= c gcc hal phy pp net80211 lwip wpa main ssl smartconfig crypto

# compiler flags using during compilation of source files
CFLAGS		= -Os -Wpointer-arith -Wundef -Werror -Wl,-EL -fno-inline-functions -nostdlib -mlongcalls -mtext-section-literals -D__ets__ -DICACHE_FLASH
#CFLAGS 		+= --rename-section .text=.irom0.text --rename-section .literal=.irom0.literal
# linker flags used to generate the main object file
LDFLAGS		= -nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static

ifeq ($(FLAVOR),debug)
    CFLAGS += -g -O0
    LDFLAGS += -g -O0
endif

ifeq ($(FLAVOR),release)
    CFLAGS += -g -O2
    LDFLAGS += -g -O2
endif


LOCAL_CONFIG_FILE:= $(wildcard include/user_config.local.h)
ifneq ("$(LOCAL_CONFIG_FILE)","")
	CFLAGS += -DLOCAL_CONFIG
endif




####
#### no user configurable options below here
####
FW_TOOL		?= $(ESPTOOL)
SRC_DIR		:= $(MODULES)
BUILD_DIR	:= $(addprefix $(BUILD_BASE)/,$(MODULES))

SDK_LIBDIR	:= $(addprefix $(SDK_BASE)/,$(SDK_LIBDIR))
SDK_INCDIR	:= $(addprefix -I$(SDK_BASE)/,$(SDK_INCDIR))

EXTRA_LIBS := $(addprefix -l,$(EXTRA_LIBS))

SRC		:= $(foreach sdir,$(SRC_DIR),$(wildcard $(sdir)/*.c))
OBJ		:= $(patsubst %.c,$(BUILD_BASE)/%.o,$(SRC))
LIBS		:= $(addprefix -l,$(LIBS))
APP_AR		:= $(addprefix $(BUILD_BASE)/,$(TARGET)_app.a)
TARGET_OUT	:= $(addprefix $(BUILD_BASE)/,$(TARGET).out)


INCDIR	:= $(addprefix -I,$(SRC_DIR))
EXTRA_INCDIR	:= $(addprefix -I,$(EXTRA_INCDIR))
MODULE_INCDIR	:= $(addsuffix /include,$(INCDIR))

V ?= $(VERBOSE)
ifeq ("$(V)","1")
Q :=
vecho := @true
else
Q := @
vecho := @echo
endif

vpath %.c $(SRC_DIR)

define compile-objects
$1/%.o: %.c
	$(vecho) "CC $$<"
	$(Q) $(CC) $(INCDIR) $(MODULE_INCDIR) $(EXTRA_INCDIR) $(SDK_INCDIR) $(CFLAGS)  -c $$< -o $$@
endef

.PHONY: all checkdirs clean

all: checkdirs $(TARGET_OUT) $(BIN_NAME)

$(BIN_NAME): $(TARGET_OUT)
	$(vecho) "FW $@"
	@$(ESPTOOL) elf2image $< -o $(FW_BASE)/$(TARGET)-



$(TARGET_OUT): $(APP_AR)
	$(vecho) "LD $@"
	$(Q) $(LD) -L$(SDK_LIBDIR) -L$(EXTRA_LIBDIR) $(LD_SCRIPT) $(LDFLAGS) -Wl,--start-group $(LIBS) $(EXTRA_LIBS) $(APP_AR) -Wl,--end-group -o $@

$(APP_AR): $(OBJ)
	$(vecho) "AR $@"
	$(Q) $(AR) cru $@ $^

checkdirs: $(BUILD_DIR) $(FW_BASE)

$(BUILD_DIR):
	$(Q) mkdir -p $@

firmware:
	$(Q) mkdir -p $@


flash:
	$(vecho) "After flash, terminal will enter serial port screen"
	$(vecho) "Please exit with command:"
	$(vecho) "\033[0;31m" "Ctrl + A + k" "\033[0m"

	@read -p "Press any key to continue... " -n1 -s
	@$(ESPTOOL) -p $(ESPPORT) write_flash 0x00000 $(FW_BASE)/$(TARGET)-0x00000.bin 0x40000 $(FW_BASE)/$(TARGET)-0x40000.bin -fs 32m
	@screen $(ESPPORT) 115200

fast: clean all flash

rebuild: clean all

clean:
	$(Q) rm -f $(APP_AR)
	$(Q) rm -f $(TARGET_OUT)
	$(Q) rm -rf $(BUILD_DIR)
	$(Q) rm -rf $(BUILD_BASE)
	$(Q) rm -f $(FW_FILE_1)
	$(Q) rm -f $(FW_FILE_2)
	$(Q) rm -rf $(FW_BASE)
	$(Q) rm -rf *.bin *.sym


$(foreach bdir,$(BUILD_DIR),$(eval $(call compile-objects,$(bdir))))
