build:
	echo "$$(luamin -f main.lua)" > main_min.lua
	./picotool/p8tool build soldier02.p8 --lua=main_min.lua
