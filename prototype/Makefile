CC     = gcc
CFLAGS = -O2 -Wall -Wextra $(shell sdl2-config --cflags)
LIBS   = $(shell sdl2-config --libs) -lSDL2_image -lm

prototype: main.c
	$(CC) $(CFLAGS) -o prototype main.c $(LIBS)

run: prototype
	./prototype

.PHONY: clean run
clean:
	-rm -f prototype
