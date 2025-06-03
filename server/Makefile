# server/Makefile

CC ?= gcc              
CFLAGS ?= -Wall -Werror -pthread
TARGET = aesdsocket
SRCS   = aesdsocket.c

.PHONY: all default clean

all: $(TARGET)
default: all

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $^ -o $@

clean:
	rm -f $(TARGET)

