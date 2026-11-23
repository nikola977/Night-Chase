class_name CityMode
extends RefCounted
## Which map the game should load: the endless world (default) or the second
## map "City Block". Set it before reloading the main scene; the main menu and
## the pause menu do exactly that.

## true = next start of main.tscn loads the city map instead of the endless world
static var enabled: bool = false
