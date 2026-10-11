TileMapBg:
BaseLayer0000: ;bg
	incbin "map/baselayer0000.ztm"
BaseLayer0000Size EQU $-BaseLayer0000
TileMapShore:
BaseLayer0001: ;shore
	incbin "map/baselayer0001.ztm"
BaseLayer0001Size EQU $-BaseLayer0001
TileMapSky:
BaseLayer0002: ;sky
	incbin "map/baselayer0002.ztm"
BaseLayer0002Size EQU $-BaseLayer0002
TileMapHud:
BaseLayer0003: ;hud
	incbin "map/baselayer0003.ztm"
BaseLayer0003Size EQU $-BaseLayer0003
TileMapSprites:
BaseLayer0004: ;sprite layer (trees, ramps, etc)
	incbin "map/baselayer0004.ztm"
BaseLayer0004Size EQU $-BaseLayer0004

Palette:
PlayerPalette:
	incbin "img/player.ztp"
PlayerPaletteSize EQU $-PlayerPalette
BgPalette:
	incbin "img/bg.ztp"
BgPaletteSize EQU $-BgPalette
TreePalette:
	incbin "img/tree.ztp"
TreePaletteSize EQU $-TreePalette
RampPalette:
	incbin "img/ramp.ztp"
	ds 24	; Pad the pallete to 16 entries (32 bytes) since the hardware reads in 16 entry chunks
RampPaletteSize EQU $-RampPalette
NumbersPalette:
	incbin "img/numbers.ztp"
	ds 16	; Pad the palette to 16 entries (32 bytes) since the hardware reads in 16 entry chunks
NumbersPaletteSize EQU $-NumbersPalette
PaletteSize EQU $-Palette

TileSet:
	dw 0 ; First entry index ofr player tile map
	dw PlayerTileSet, PlayerTileSetSize
	dw 64 ; First entry index for background tile map
	dw BgTileSet, BgTileSetSize
	dw 128 ; First entry index for tree tile map
	dw TreeTileSet, TreeTileSetSize
	dw 160; First entry index for ramp tile map
	dw RampTileSet, RampTileSetSize
	dw 192 ; First entry index for numbers tile map
	dw NumbersTileSet, NumbersTileSetSize
	dw 0xffff	; Terminator for the tile map
	dw 0,0	; End of tile map

PlayerTileSet:
	incbin "img/player.zts.zx0"
PlayerTileSetSize EQU $-PlayerTileSet
BgTileSet:
	incbin "img/bg.zts.zx0"
BgTileSetSize EQU $-BgTileSet
TreeTileSet:
	incbin "img/tree.zts.zx0"
TreeTileSetSize EQU $-TreeTileSet
RampTileSet:
	incbin "img/ramp.zts.zx0"
RampTileSetSize EQU $-RampTileSet
NumbersTileSet:
	incbin "img/numbers.zts.zx0"
NumbersTileSetSize EQU $-NumbersTileSet
EndOfLine:
