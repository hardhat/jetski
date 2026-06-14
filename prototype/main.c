#include <stdint.h>
#include <stdbool.h>

#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>

#include "course_index.h"

SDL_Renderer *renderer;

#define WIDTH 320
#define HEIGHT 240

typedef struct { 
    uint8_t segment;
    // Player boat position
    int16_t pos_z; // in cm from beginning of segment
    int16_t pos_x; // in cm from centre of segment (following the curve)
    uint16_t velocity; // in m/s?
    uint16_t acceleration; // in m/s^2?
} MapState;

typedef struct { SDL_Texture *t; int w, h; } Tex;

Tex texture;

static Tex load_tex(SDL_Renderer *r, const char *path) {
    SDL_Surface *s = IMG_Load(path);
    if (!s) {
        fprintf(stderr, "IMG_Load(%s): %s\n", path, IMG_GetError());
        return (Tex){NULL, 0, 0};
    }
    Tex tx = { SDL_CreateTextureFromSurface(r, s), s->w, s->h };
    SDL_FreeSurface(s);
    return tx;
}

void fill_rect(int x,int y,int w,int h)
{
    SDL_Rect rect={x,y,w,h};
    SDL_RenderFillRect(renderer,&rect);
}

void draw(void)
{
    // Sky: First 64 lines in cyan.
    SDL_SetRenderDrawColor(renderer,0,255,255,255);
    fill_rect(0,0,WIDTH,64);
    // Water: Medium blue
    SDL_SetRenderDrawColor(renderer, 64,64,255,255);
    fill_rect(0,64,WIDTH,HEIGHT-64);

    //  Boat
    SDL_SetRenderDrawColor(renderer, 255,255,255,255);
    fill_rect(WIDTH/2-48/2,HEIGHT-68,48,64);
}

void update(void)
{

}

int main(int argc,char **argv)
{
    (void)argc;
    (void)argv;
    SDL_Init(SDL_INIT_VIDEO);
    IMG_Init(IMG_INIT_PNG);
    
    SDL_Window *window = SDL_CreateWindow("SDL2 Window", SDL_WINDOWPOS_CENTERED, 
        SDL_WINDOWPOS_CENTERED, WIDTH*2, HEIGHT*2, 0);
    renderer = SDL_CreateRenderer(window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);

    texture = load_tex(renderer, "../img/player.png");


    SDL_RenderSetLogicalSize(renderer, WIDTH, HEIGHT);

    bool done=false;
    while(!done) {
        SDL_Event event;
        while(SDL_PollEvent(&event))
        {
            switch(event.type) {
                case SDL_QUIT:
                    done=true;
                    break;
                case SDL_KEYDOWN:
                    if(event.key.keysym.sym==SDLK_ESCAPE) {
                        done=true;
                    }
                    break;
                case SDL_KEYUP:
                    break;
            }
        }
        update();
        draw();
        SDL_RenderPresent(renderer);
    }

    // Clean up
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}