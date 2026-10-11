#CC     = x86_64-w64-mingw32-gcc
#SDL2CONFIG = /usr/x86_64-w64-mingw32/sys-root/mingw/bin/sdl2-config
SDL2CONFIG = sdl2-config
CFLAGS = -O2 -Wall -Wextra $(shell $(SDL2CONFIG) --cflags)
LIBS   = $(shell $(SDL2CONFIG) --libs) -lSDL2_image -lm

prototype: main.c
	$(CC) $(CFLAGS) -o prototype main.c $(LIBS)

run: prototype
	./prototype

.PHONY: clean run
clean:
	-rm -f prototype
