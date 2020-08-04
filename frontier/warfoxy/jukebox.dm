/datum/client_preference/play_jukeboxes
	description ="Play jukeboxes"
	key = "SOUND_JUKEBOXES"

/datum/track
	var/title
	var/track

/datum/track/New(var/title, var/track)
	src.title = title
	src.track = track

datum/track/proc/GetTrack()
	if(ispath(track, /music_track))
		var/music_track/music_track = decls_repository.get_decl(track)
		return music_track.song
	return track // Allows admins to continue their adminbus simply by overriding the track var

/obj/machinery/media/jukebox
	name = "mediatronic jukebox"
	desc = "An immense, standalone touchscreen on a swiveling base, equipped with phased array speakers. Embossed on one corner of the ultrathin bezel is the brand name, 'Leitmotif Enterprise Edition'."
	icon = 'icons/obj/jukebox_new.dmi'
	icon_state = "jukebox3-nopower"
	var/state_base = "jukebox3"
	anchored = 1
	density = 1
	power_channel = EQUIP
	idle_power_usage = 10
	active_power_usage = 100
	clicksound = 'sound/machines/buttonbeep.ogg'
	pixel_x = -8

	var/playing = 0
	var/volume = 20

	var/sound_id
	var/datum/sound_token/sound_token

	var/datum/track/current_track
	var/list/datum/track/tracks

/obj/machinery/media/jukebox/old
	name = "space jukebox"
	desc = "A battered and hard-loved jukebox in some forgotten style, carefully restored to some semblance of working condition."
	icon = 'icons/obj/jukebox.dmi'
	icon_state = "jukebox2-nopower"
	state_base = "jukebox2"
	pixel_x = 0

/obj/machinery/media/jukebox/New()
	..()
	update_icon()
	sound_id = "[/obj/machinery/media/jukebox]_[sequential_id(/obj/machinery/media/jukebox)]"

/obj/machinery/media/jukebox/Initialize()
	. = ..()
	tracks = setup_music_tracks(tracks)

/obj/machinery/media/jukebox/Destroy()
	StopPlaying()
	QDEL_NULL_LIST(tracks)
	current_track = null

	if(tape) // INF@CODE
		QDEL_NULL(tape)

	. = ..()

/obj/machinery/media/jukebox/powered()
	return anchored && ..()

/obj/machinery/media/jukebox/power_change()
	. = ..()
	if(stat & (NOPOWER|BROKEN) && playing)
		StopPlaying()

/obj/machinery/media/jukebox/on_update_icon()
	overlays.Cut()
	if(stat & (NOPOWER|BROKEN) || !anchored)
		if(stat & BROKEN)
			icon_state = "[state_base]-broken"
		else
			icon_state = "[state_base]-nopower"
		return
	icon_state = state_base
	if(playing)
		if(emagged)
			overlays += "[state_base]-emagged"
		else
			overlays += "[state_base]-running"

/obj/machinery/media/jukebox/CanUseTopic(user, state)
	if(!anchored)
		to_chat(user, "<span class='warning'>You must secure \the [src] first.</span>")
		return STATUS_CLOSE
	return ..()

/obj/machinery/media/jukebox/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1)
	var/list/juke_tracks = new
	for(var/datum/track/T in tracks)
		juke_tracks.Add(list(list("track"=T.title)))

	var/list/data = list(
		"current_track" = current_track != null ? current_track.title : "No track selected",
		"playing" = playing,
		"tracks" = juke_tracks,
		"volume" = volume,
		"tape" = tape
	)

	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "jukebox.tmpl", "Your Media Library", 340, 440)
		ui.set_initial_data(data)
		ui.open()

/obj/machinery/media/jukebox/OnTopic(var/mob/user, var/list/href_list, state)
	if (href_list["title"])
		for(var/datum/track/T in tracks)
			if(T.title == href_list["title"])
				current_track = T
				StartPlaying()
				break
		return TOPIC_REFRESH

	if (href_list["stop"])
		StopPlaying()
		return TOPIC_REFRESH

	if (href_list["play"])
		if(emagged)
			emag_play()
		else if(!current_track)
			to_chat(usr, "No track selected.")
		else
			StartPlaying()
		return TOPIC_REFRESH

	if (href_list["volume"])
		AdjustVolume(text2num(href_list["volume"]))
		return TOPIC_REFRESH

	if (href_list["eject"])
		eject()
		return TOPIC_REFRESH

/obj/machinery/media/jukebox/proc/emag_play()
	playsound(loc, 'sound/items/AirHorn.ogg', 100, 1)
	for(var/mob/living/carbon/M in ohearers(6, src))
		if(istype(M, /mob/living/carbon/human))
			var/mob/living/carbon/human/H = M
			if(H.get_sound_volume_multiplier() < 0.2)
				continue
		M.sleeping = 0
		M.stuttering += 20
		M.ear_deaf += 30
		M.Weaken(3)
		if(prob(30))
			M.Stun(10)
			M.Paralyse(4)
		else
			M.make_jittery(400)
	spawn(15)
		explode()

/obj/machinery/media/jukebox/interface_interact(var/mob/user)
	ui_interact(user)
	return TRUE

/obj/machinery/media/jukebox/proc/explode()
	walk_to(src,0)
	src.visible_message("<span class='danger'>\the [src] blows apart!</span>", 1)

	explosion(src.loc, 0, 0, 1, rand(1,2), 1)

	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(3, 1, src)
	s.start()

	new /obj/effect/decal/cleanable/blood/oil(src.loc)
	qdel(src)

/obj/machinery/media/jukebox/attackby(obj/item/W as obj, mob/user as mob)
	if(isWrench(W))
		add_fingerprint(user)
		wrench_floor_bolts(user, 0)
		power_change()
		return

	// INF@CODE - START
	if(istype(W, /obj/item/music_tape))
		var/obj/item/music_tape/D = W
		if(tape)
			to_chat(user, "<span class='notice'>There is already \a [tape] inside.</span>")
			return

		if(D.ruined)
			to_chat(user, "<span class='warning'>\The [D] is ruined, you can't use it.</span>")
			return

		visible_message("<span class='notice'>[usr] insert \the [tape] in to \the [src].</span>")
		user.drop_item()
		D.forceMove(src)
		tape = D
		tracks += tape.track
		verbs += /obj/machinery/media/jukebox/verb/eject
		return
	// INF@CODE - END

	return ..()

/obj/machinery/media/jukebox/emag_act(var/remaining_charges, var/mob/user)
	if(!emagged)
		emagged = 1
		StopPlaying()
		visible_message("<span class='danger'>\The [src] makes a fizzling sound.</span>")
		update_icon()
		return 1

/obj/machinery/media/jukebox/proc/StopPlaying()
	playing = 0
	update_use_power(POWER_USE_IDLE)
	update_icon()
	QDEL_NULL(sound_token)


/obj/machinery/media/jukebox/proc/StartPlaying()
	StopPlaying()
	if(!current_track)
		return

	// Jukeboxes cheat massively and actually don't share id. This is only done because it's music rather than ambient noise.
	sound_token = GLOB.sound_player.PlayLoopingSound(src, sound_id, current_track.GetTrack(), volume = volume, range = 7, falloff = 3, prefer_mute = TRUE, preference = /datum/client_preference/play_jukeboxes)

	playing = 1
	update_use_power(POWER_USE_ACTIVE)
	update_icon()

/obj/machinery/media/jukebox/proc/AdjustVolume(var/new_volume)
	volume = Clamp(new_volume, 0, 50)
	if(sound_token)
		sound_token.SetVolume(volume)

//Custom pre-made cassetes
/obj/item/music_tape/title2
	name = "Title 2"
	track = new /datum/track("Title 2", 'sound/music/title2.ogg')
	rewrites_left = 0

/obj/item/music_tape/clouds
	name = "Clouds"
	track = new /datum/track("Clouds of Fire", /music_track/clouds_of_fire)
	rewrites_left = 0

/obj/item/music_tape/custom
	name = "dusty tape"
	desc = "A dusty tape, which can hold anything. Only what you need is blow the dust away and you will be able to play it again."

// Music tape code :3
/obj/item/music_tape
	name = "music tape"
	desc = "Magnetic tape adapted to outdated but proven music formats such as midi, wav and module files."
	icon = 'icons/obj/device.dmi'
	icon_state = "tape_white"
	item_state = "analyzer"
	w_class = ITEM_SIZE_TINY
	force = 1
	throwforce = 0

	matter = list(MATERIAL_PLASTIC = 20, MATERIAL_STEEL = 5, MATERIAL_GLASS= 5)

	var/random_color = TRUE
	var/ruined = 0
	var/rewrites_left = 3

	var/list/datum/track/track
	var/uploader_ckey

/obj/item/music_tape/Initialize()
	. = ..()
	if(random_color)
		icon_state = "tape_[pick("white", "blue", "red", "yellow", "purple")]"

/obj/item/music_tape/on_update_icon()
	overlays.Cut()
	if(ruined)
		overlays += "ribbonoverlay"

/obj/item/music_tape/examine(mob/user)
	. = ..(user)
	if(track) to_chat(user, SPAN_NOTICE("It's labeled as \"[track.title]\"."))

/obj/item/music_tape/attack_self(mob/user)
	if(!ruined)
		to_chat(user, SPAN_NOTICE("You pull out all the tape!"))
		ruin()

/obj/item/music_tape/attackby(obj/item/I, mob/user, params)
	if(ruined && (isScrewdriver(I) || istype(I, /obj/item/weapon/pen)))
		to_chat(user, SPAN_NOTICE("You start winding \the [src] back in..."))
		if(do_after(user, 120, target = src))
			to_chat(user, SPAN_NOTICE("You wound \the [src] back in."))
			fix()
		return
	/*
	if(istype(I, /obj/item/weapon/pen))
		if(loc == user && !user.incapacitated())
			var/new_name = input(user, "What would you like to label \the [src]?", "\improper [src] labeling") as null|text
			if(isnull(new_name)) return

			new_name = sanitizeSafe(new_name)

			if(new_name)
				SetName("[src] - \"[new_name]\"")
				to_chat(user, SPAN_NOTICE("You label \the [src] '[new_name]'."))
			else
				SetName("[src]")
				to_chat(user, SPAN_NOTICE("You scratch off the label."))
		return */
	..()

/obj/item/music_tape/fire_act()
	ruin()

/obj/item/music_tape/custom/attack_self(mob/user)
	if(!ruined && !track)
		if(setup_tape(user))
			log_and_message_admins("uploaded new sound <a href='?_src_=holder;listen_tape_sound=\ref[track.track]'>(preview)</a> in <a href='?_src_=holder;adminplayerobservefollow=\ref[src]'>\the [src]</a> with track name \"[track.title]\". <A HREF='?_src_=holder;wipe_tape_data=\ref[src]'>Wipe</A> data.")
		return
	..()

/obj/item/music_tape/custom/proc/setup_tape(mob/user)
	var/sound_file = input(user, "Pick sound:","File") as null|sound
	if(isnull(sound_file)) return 0

	var/new_name = input(user, "Name \the [src]:") as null|text
	if(isnull(new_name)) return 0

	new_name = sanitizeSafe(new_name)

/*	if(new_name)
		SetName("[src] - \"[new_name]\"")*/

	if(sound_file && new_name)
		track = new /datum/track(new_name, sound_file)
		return 1
	return 0

/obj/item/music_tape/proc/CanPlay()
	if(!track)
		return FALSE

	if(ruined)
		return FALSE

	return TRUE

/obj/item/music_tape/proc/ruin()
	ruined = TRUE
	update_icon()

/obj/item/music_tape/proc/fix()
	ruined = FALSE
	update_icon()

/obj/machinery/media/jukebox
	var/obj/item/music_tape/tape

/obj/machinery/media/jukebox/verb/eject()
	set name = "Eject"
	set category = "Object"
	set src in oview(1)

	if(!CanPhysicallyInteract(usr))
		return

	if(tape)
		StopPlaying()
		current_track = null
		for(var/datum/track/T in tracks)
			if(T == tape.track)
				tracks -= T
		visible_message(SPAN_NOTICE("[usr] eject \the [tape] from \the [src]."))
		usr.put_in_hands(tape)
		tape = null
		verbs -= /obj/machinery/media/jukebox/verb/eject
