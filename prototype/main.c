#include <stdint.h>
#include <stdbool.h>

#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>

#include "course_index.h"

SDL_Renderer *renderer;

#define WIDTH 320
#define HEIGHT 240

#define MAX_SPEED 46*256 // 46cm/frame = 100km/h
// These values are in cm/frame/256 (fixed point)
#define ACCELERATION 75
#define COAST 25
#define BREAK 150

// These values are in degrees, and represent how much the steering wheel is turned by the player. They are not the actual steering effect, which is calculated based on yaw and speed.
#define YAW 1
#define STEER_MAX 16

// pseudo-3D distannce of the player from the camera, in cm. This is used to calculate the size of sprites and the perspective effect.
#define NEAR 256
#define FAR 25000
#define Y_WORLD 2500    // 30m above the water surface, for the position of the camera and the trees. This is used to calculate the perspective effect and the vertical position of sprites.

typedef struct {
    // Current track state
    const char *course_name;
    TrackSegment *segments;
    uint16_t segment_count;
    uint8_t segment;
    // Player boat position
    int16_t world_pos_z; // in cm from beginning of segment
    int16_t world_pos_x; // in cm from centre of segment (following the curve)
    int16_t velocity; // in cm/frame*256 (fixed point) (46cm/frame = 100km/h)
    int16_t throttle;   // How much acceleration on the engine
    int16_t yaw;    // Steering wheel direction
    int16_t steer;  // How much to steer the boat, based on yaw and speed
} MapState;

MapState state;

typedef struct { SDL_Texture *t; int w, h; } Tex;

Tex player_texture;
Tex numbers;
Tex tree;

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

/* Blit a sprite: horizontal centre at cx, bottom edge at bot, scaled by sc */
void blit(SDL_Renderer *r, Tex *tx, SDL_Rect *src,
                 float cx, float bot, float sc) {
    if (!tx || !tx->t || sc < 0.002f) return;
    SDL_Rect s = src ? *src : (SDL_Rect){0, 0, tx->w, tx->h};
    int dw = SDL_max(1, (int)(s.w * sc));
    int dh = SDL_max(1, (int)(s.h * sc));
    SDL_Rect d = { (int)cx - dw / 2, (int)bot - dh, dw, dh };
    SDL_RenderCopy(r, tx->t, &s, &d);
}

static void draw_tile(Tex *tex, int tile_index, int x, int y)
{
    SDL_Rect src = { tile_index*16%tex->w, tile_index*16/tex->w*16, 16, 16 };
    SDL_RenderCopy(renderer, tex->t, &src, &(SDL_Rect){x,y,16,16});
}

void fill_rect(int x,int y,int w,int h)
{
    SDL_Rect rect={x,y,w,h};
    SDL_RenderFillRect(renderer,&rect);
}

void find_track(const char *name)
{
    for(uint16_t i=0;i<g_course_index_count;i++) {
        if(strcmp(name,g_course_index[i].name)==0) {
            state.course_name = g_course_index[i].name;
            state.segments = (TrackSegment*)g_course_index[i].segments;
            state.segment_count = g_course_index[i].segment_count;
            return;
        }
    }
    // Not found, exit with printed error.
    printf("Could not find track '%s'\nSupported tracks:\n", name);
    // Print possible track names
    for(int i=0;i<g_course_index_count;i++) {
        printf("   %s\n",g_course_index[i].name);
    }
    exit(10);
}

void draw_number(int value,int x,int y)
{
    char buffer[16];

    sprintf(buffer,"%d",value);

    for(size_t i=0;i<strlen(buffer);i++)
    {
        char c = buffer[i];
        if(c!='-' && (c<'0' || c>'9')) continue;
        int digit = c - '0';
        if(c=='-') digit=11; // Dash is the 12th tile in the texture
        draw_tile(&numbers, digit, x+i*16, y);
    }
}

void draw(void)
{
    // Hud: first 16 lines in dark blue
    SDL_SetRenderDrawColor(renderer, 8,8,24,255);
    fill_rect(0,0,WIDTH,16);
    // Sky: Next 48 lines in cyan.
    SDL_SetRenderDrawColor(renderer,0,255,255,255);
    fill_rect(0,16,WIDTH,48);
    // Water: Medium blue
    SDL_SetRenderDrawColor(renderer, 64,64,255,255);
    fill_rect(0,64,WIDTH,HEIGHT-64);

    //  Boat
    SDL_SetRenderDrawColor(renderer, 255,255,255,255);
    fill_rect(WIDTH/2-48/2,HEIGHT-68,48,64);

    // Show segment, speed in the top left
    // (Using the numbers texture for digits, and letters from the player texture)
    draw_number(state.segment, 0, 0);
    draw_number(state.world_pos_z, 16*4, 0);
    draw_number(state.yaw, 16*10, 0);
    draw_number(state.velocity>>8, WIDTH-64, 0);

    int cumulative_z = -state.world_pos_z; // Start with the z position of the player within the current segment
    int old_lane_x = WIDTH/2; // Start with the lane position at the centre of the screen
    int old_lane_y = HEIGHT; // Start with the lane position at the bottom of the screen
    for(int i=0;i<state.segment_count;i++) {
        TrackSegment *seg = &state.segments[i];
        if(i<state.segment) continue; // Skip segments behind the player

        // The z position of the segment relative to the player
        int z = cumulative_z + seg->length;
        cumulative_z += seg->length;
        // Far plane clipping at 25000 cm (2.5km)
        if(z>25000) break;
        int x = WIDTH/2 + seg->curve*4;
        int y = HEIGHT - Y_WORLD*NEAR/z; // Perspective effect: the further away, the closer to the horizon 
        printf("Segment %d: z=%d, x=%d, y=%d\n", i, z, x, y);
        if(y<-16) break; // Off the top of the screen
        if(y>HEIGHT) continue; // Off the bottom of the screen
        draw_tile(&tree, 6, x-16, y-16);
        draw_tile(&tree, 14, x+16, y-16);

        // Draw the 10m wide lane as a line to either side
        SDL_SetRenderDrawColor(renderer, 255,255,255,255);
        int lane_width = 10*4; // 10m wide lane, scaled by
        int lane_x = WIDTH/2 + seg->curve*4; // Lane position based on curve
        int lane_y = HEIGHT - Y_WORLD*NEAR/z; // Perspective effect: the further away, the closer to the horizon
        SDL_RenderDrawLine(renderer, lane_x-lane_width, lane_y, lane_x+lane_width, lane_y);
        // Draw left lane edge, from old to current segment, to create a continuous line. This is a bit hacky but it works for now.
        SDL_RenderDrawLine(renderer, old_lane_x-lane_width, old_lane_y, lane_x-lane_width, lane_y);
        // Draw right lane edge, from old to current segment, to create a continuous line. This is a bit hacky but it works for now.
        SDL_RenderDrawLine(renderer, old_lane_x+lane_width, old_lane_y, lane_x+lane_width, lane_y);
        old_lane_x = lane_x;
        old_lane_y = lane_y;
    }
}

void update(void)
{
    // Use throttle to update velocity and world pos
    state.velocity += state.throttle - COAST;
    // Clamp
    if(state.velocity<0) state.velocity=0;
    if(state.velocity>MAX_SPEED) state.velocity=MAX_SPEED;
    // End of segment?
    state.world_pos_z += (state.velocity >> 8); // Divide by 256 to convert from fixed point
    TrackSegment *seg = &state.segments[state.segment];
    if(state.world_pos_z>seg->length) {
        state.world_pos_z -= seg->length;
        state.segment++;
        if(state.segment>=state.segment_count) {
            state.segment=0;
        }
    }
    // Update steering based on yaw and speed
    // The faster you go, the more your yaw affects your steer, up to a maximum
    state.steer = (state.yaw * state.velocity) / MAX_SPEED;
    if(state.steer > STEER_MAX) state.steer = STEER_MAX;
    if(state.steer < -STEER_MAX) state.steer = -STEER_MAX;
}

int main(int argc,char **argv)
{
    SDL_Init(SDL_INIT_VIDEO);
    IMG_Init(IMG_INIT_PNG);
    
    SDL_Window *window = SDL_CreateWindow("SDL2 Window", SDL_WINDOWPOS_CENTERED, 
        SDL_WINDOWPOS_CENTERED, WIDTH*2, HEIGHT*2, 0);
    renderer = SDL_CreateRenderer(window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);

    player_texture = load_tex(renderer, "../img/player.png");
    numbers = load_tex(renderer, "../img/numbers.png");
    tree = load_tex(renderer, "../img/tree.png");

    SDL_RenderSetLogicalSize(renderer, WIDTH, HEIGHT);

    if(argc>1) {
        find_track(argv[1]);
    } else {
        state.course_name = g_course_index[0].name;
        state.segments = (TrackSegment*)g_course_index[0].segments;
        state.segment_count = g_course_index[0].segment_count;
    }

    bool done=false;
    uint32_t last_time = SDL_GetTicks();
    while(!done) {
        SDL_Event event;
        while(SDL_PollEvent(&event))
        {
            switch(event.type) {
                case SDL_QUIT:
                    done=true;
                    break;
                case SDL_KEYDOWN:
                    switch(event.key.keysym.sym) {
                        case SDLK_ESCAPE:
                            done=true;
                            break;
                        case SDLK_LEFT:
                            state.yaw=-YAW;
                            break;
                        case SDLK_RIGHT:
                            state.yaw=YAW;
                            break;
                        case SDLK_UP:
                            state.throttle=ACCELERATION;
                            break;
                        case SDLK_DOWN:
                            state.throttle=-BREAK;
                            break;
                        case SDLK_SPACE:
                            //state.velocity+=boost;
                            break;
                    }
                    break;
                case SDL_KEYUP:
                    switch(event.key.keysym.sym) {
                        case SDLK_LEFT:
                            state.yaw=0;
                            break;
                        case SDLK_RIGHT:
                            state.yaw=0;
                            break;
                        case SDLK_UP:
                            state.throttle=0;
                            break;
                        case SDLK_DOWN:
                            state.throttle=0;
                            break;
                    }
                    break;
            }
        }
        update();
        draw();
        SDL_RenderPresent(renderer);
        uint32_t current_time = SDL_GetTicks();
        uint32_t elapsed_time = current_time - last_time;
        if(elapsed_time < 16) {
            SDL_Delay(16 - elapsed_time);
        }
        last_time = current_time;
    }

    // Clean up
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}