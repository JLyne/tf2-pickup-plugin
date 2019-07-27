# tf2-pickup-plugin

[Originally showcased by RTGame](https://www.youtube.com/watch?v=6SHx4wfeucc)

Sourcemod plugin that allows you to pickup pretty much anything ingame, using `logic_measure_movement`s.

## Features

* Pick up things!
* Drop things!
* Terrorise other players!
* Cause lag!

## Commands
* `/pickup` - Pick up the entity you are aiming at
* `/drop` - Drop the last entity you picked up at your current position
* `/put` - Place the last entity you picked up where you are aiming
* `/dropall` - Drop everything you picked up

##Notes
* Only works with entities naturally, so most map geometry is out. Anything dynamic should be cool though, as long as you can aim at it.
* You can pick things up at any time, as long as you can see them. This includes while dead and spectating.
* While spectating, anything you picked up will appear on the spectated player
* Picking up trains is not advised if you want to continue being alive
* If you pick up a player, they will repeatedly take fall damage
* If you pick up a teleporter exit, anyone using it will inherit the teleporters angles, this affects their controls too
