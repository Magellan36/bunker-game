extends RefCounted
class_name NPCDialogue
## NPCDialogue.gd (Sep 2026; pools formerly inline in NPC.gd).
##
## Sep 2026 (Brannon): residents only say things that show the player their
## state — mood, condition, wants, dislikes, how they feel about you — and
## nothing between residents (no overhead chat). Every line here is a
## placeholder; Brannon will replace them all with his own writing.
##
## Line selection for the resident panel's "Talk" and "Ask about". Picks in
## priority order so what a resident says always matches what the player
## can see going on with them:
##   1. Temper      — Mad/Rage residents are short with everyone.
##   2. Feelings about the player — a Hostile resident never greets you
##      warmly just because their mood happens to be high.
##   3. Pressing needs — starving/parched/exhausted residents say so.
##   4. What's on their mind — often (not always) they bring up their
##      strongest recent thought: the hot meal, the night on the floor,
##      the argument with Dez, the gift from Mara...
##   5. General mood.

const ANGRY: Array[String] = [
	"\"What do you want.\"",
	"\"Not now.\"",
	"\"I'm this close to losing it.\"",
]
const FRUSTRATED: Array[String] = [
	"\"...Yeah?\"",
	"\"Can this wait?\"",
	"\"Make it quick.\"",
]
const GRUMPY: Array[String] = [
	"\"Hm. What.\"",
	"\"Yeah, yeah.\"",
]
const LOW_MOOD: Array[String] = [
	"\"...\"",
	"\"I don't really feel like talking.\"",
	"\"Some days I wonder what we're even doing down here.\"",
]
const HAPPY: Array[String] = [
	"\"Hey! Good to see you.\"",
	"\"Honestly? Today's not bad.\"",
]
const NEUTRAL: Array[String] = [
	"\"...Yeah?\"",
	"\"Hey.\"",
	"\"Need something?\"",
]
const TOWARD_PLAYER_HOSTILE: Array[String] = [
	"\"You've got some nerve talking to me.\"",
	"\"Keep walking.\"",
	"\"I've got nothing to say to you.\"",
]
const TOWARD_PLAYER_COLD: Array[String] = [
	"\"...What.\"",
	"\"If this is about work, just say it.\"",
	"\"Mm.\"",
]
## How they feel about YOU, beyond the relationship word (fear, grudges,
## gratitude) — so the player reads it from what they say, not a number.
const TOWARD_PLAYER_AFRAID: Array[String] = [
	"\"Please — I don't want any trouble.\"",
	"\"I'll do whatever you want. Just... stay over there.\"",
	"\"W-what do you need?\"",
	"\"I'm going, I'm going. Don't.\"",
]
const TOWARD_PLAYER_WARY: Array[String] = [
	"\"...You need something?\"",
	"\"I'm keeping my head down. Alright?\"",
	"\"Didn't do anything. Just so you know.\"",
]
const TOWARD_PLAYER_GRUDGE: Array[String] = [
	"\"I haven't forgotten what you did.\"",
	"\"Don't act like nothing happened.\"",
	"\"You've got a short memory. I don't.\"",
	"\"Funny, you talking to me like we're fine.\"",
]
const TOWARD_PLAYER_FURIOUS: Array[String] = [
	"\"Get away from me.\"",
	"\"Don't. Don't even start.\"",
	"\"You. Of all people.\"",
]
const TOWARD_PLAYER_GRATEFUL: Array[String] = [
	"\"I wouldn't be standing here if it weren't for you.\"",
	"\"I owe you. I mean it.\"",
	"\"Still can't believe you came through for me.\"",
]
## Mid crash-out, whatever the player says.
const CRASH_GREETING: Dictionary = {
	"hostile":   ["\"Not. Now.\"", "\"Back off. I mean it.\"", "\"Leave me alone before I do something.\""],
	"overdrive": ["\"Can't talk. Working.\"", "\"Later. There's too much to do.\"", "\"Move — I need to get past.\""],
	"breakdown": ["\"Please... just leave me alone.\"", "\"*doesn't look up*\"", "\"I can't. Not right now.\""],
}
## Close to snapping (at crash-out risk).
const BREAKING_POINT: Array[String] = [
	"\"I'm not okay. I'm really not okay.\"",
	"\"One more thing. One more thing goes wrong and I'm done.\"",
	"\"Don't push me today. Please.\"",
	"\"I can feel it slipping. Whatever 'it' is.\"",
]
## Grieving someone who died.
const GRIEF: Array[String] = [
	"\"I keep thinking about %s.\"",
	"\"%s should still be here.\"",
	"\"It's so quiet without %s.\"",
	"\"...Sorry. I'm just thinking about %s.\"",
]
## The bunker condition dragging their mood down the most (NPCMorale ids),
## said when their mood is low — so the player knows what to fix.
const CONDITION_BAD: Dictionary = {
	"light":   ["\"It's so dark down here I can't think straight.\"", "\"Can we get some light in here? Anything?\""],
	"power":   ["\"The power cut out again. How are we supposed to live like this?\"", "\"Every time the lights flicker my heart stops.\""],
	"water":   ["\"The water tastes like rust. It can't be safe.\"", "\"I'm scared to drink the water.\""],
	"food":    ["\"Another cold can. I'm so sick of cold cans.\"", "\"When did we last eat a real meal?\""],
	"rest":    ["\"I haven't slept properly in days.\"", "\"I'm running on nothing.\""],
	"space":   ["\"No bed, no room, junk everywhere. It's a pit.\"", "\"There's nowhere to even breathe in here.\""],
	"safety":  ["\"I don't feel safe down here anymore.\"", "\"After what happened... I keep looking over my shoulder.\""],
	"company": ["\"Nobody really talks to each other down here.\"", "\"Some of these people... I can't stand being around them.\""],
}
const CONDITION_GOOD: Dictionary = {
	"light":   ["\"Nice to actually see where I'm going for once.\""],
	"power":   ["\"Power's been steady. Small mercies.\""],
	"water":   ["\"The water's actually clean now. Didn't think I'd miss that.\""],
	"food":    ["\"We've been eating well. Feels almost normal.\""],
	"rest":    ["\"I've been sleeping well. Makes all the difference.\""],
	"space":   ["\"The place is starting to feel like home.\""],
	"safety":  ["\"It feels safe down here. For now.\""],
	"company": ["\"The people down here are alright. Really.\""],
}

const TOWARD_PLAYER_CLOSE: Array[String] = [
	"\"There you are! I was hoping you'd stop by.\"",
	"\"Glad you're around. Seriously.\"",
	"\"Hey, you. What's the plan today?\"",
]

const HUNGRY: Array[String] = [
	"\"I'm starving. Is there anything to eat down here?\"",
	"\"When did I last eat? I can't even remember.\"",
]
const THIRSTY: Array[String] = [
	"\"My mouth's like sandpaper. We need water.\"",
	"\"Is there any water left? Anything?\"",
]
const EXHAUSTED: Array[String] = [
	"\"I can barely keep my eyes open.\"",
	"\"I need to lie down before I fall down.\"",
]

## thought id -> lines. "%s" = the thought's subject.
const ON_MIND: Dictionary = {
	"ate_hot_meal":      ["\"That hot meal earlier? Exactly what I needed.\"", "\"Real cooked food. Felt human again for a minute.\""],
	"ate_fresh":         ["\"Had something fresh from the garden. Tasted like before.\""],
	"ate_cold_can":      ["\"Another cold can. I'd kill for a hot meal.\"", "\"Canned food again. It keeps you alive, I guess.\""],
	"slept_in_bed":      ["\"Slept like a rock last night.\"", "\"A real bed makes all the difference.\""],
	"slept_in_chair":    ["\"Fell asleep in a chair. My neck is not happy.\""],
	"slept_on_floor":    ["\"Slept on the floor. My back is killing me.\"", "\"We need more beds down here. The floor is concrete.\""],
	"collapsed":         ["\"I pushed too hard and just... blacked out.\"", "\"Woke up on the floor. Don't ask.\""],
	"bad_chat":          ["\"%s and I got into it earlier. Don't ask.\"", "\"If %s says one more thing to me...\""],
	"got_snatched":      ["\"%s snatched my food right out of my hands.\"", "\"Watch %s. They'll take the food out of your mouth.\""],
	"food_taken":        ["\"Someone took my food while I was eating. Who does that?\""],
	"break_interrupted": ["\"I was on a break, you know.\""],
	"cluttered":         ["\"This place is a mess. Someone should tidy up.\"", "\"I keep tripping over junk down here.\""],
	"in_pain":           ["\"Everything hurts.\"", "\"I'm not in great shape right now.\""],
	"lonely":            ["\"Feels like nobody talks to each other down here.\""],
	"crowded_beds":      ["\"Would be nice to have a bed I could count on.\""],
	"insulted":          ["\"I heard what you said. I'm not deaf.\"", "\"Nice words earlier. Really.\""],
	"threatened":        ["\"You threatened me. I'm not going to forget that.\"", "\"I'm doing what you said. Happy?\""],
	"under_pressure":    ["\"Everyone's breathing down my neck.\""],
	"cowed":             ["\"I'm not going to cause trouble. Okay?\""],
	"burned_out":        ["\"I think I worked myself into the ground.\"", "\"I've got nothing left. Nothing.\""],
	"vented_rage":       ["\"I lost it earlier. I... needed that, I think.\"", "\"Sorry about before. I'm calmer now.\""],
	"cried_it_out":      ["\"I'm alright. I just needed a minute. Or an hour.\""],
	"body_in_bunker":    ["\"There's a body in here. A BODY. And we just... walk past it?\"", "\"I can't stop looking at it. Can we do something with it?\""],
	"weapon_fight":      ["\"After that fight... I jump at every sound.\"", "\"Someone could've been killed. Someone WAS.\""],
	"near_body":         ["\"I have to work right next to it. Every day. Can't we move it?\"", "\"Don't make me go near that corner again.\""],
	"relieved":          ["\"%s is gone. I'm not going to pretend I'm sad.\"", "\"Can't say I'll miss %s.\""],
	"unsafe_with":       ["\"I have to live next to the person who attacked me. Think about that.\""],
	"patched_up":        ["\"%s patched me up. Good people.\""],
	"was_attacked":      ["\"%s hit me. Just — hit me.\"", "\"Keep %s away from me.\"", "\"My face still hurts. Thanks, %s.\""],
	"saw_fight":         ["\"Did you see what happened to %s?\"", "\"I can't stop thinking about the fight.\""],
	"saved_me":          ["\"%s saved my life. I won't forget it.\""],
	"broke_up_fight":    ["\"Somebody had to pull them apart.\""],
	"backed_down":       ["\"I backed off from %s. Wasn't worth it.\"", "\"%s wanted a fight. I didn't.\""],
	"talked_down":       ["\"%s talked me down. Probably a good thing.\""],
}
const ON_MIND_CHANCE: float = 0.55

## Relationship Q&A ("What do you think of X?") — answers from THAT
## relationship, not from the asked NPC's own mood.
const REL_HOSTILE: Array[String] = ["\"I hate them.\"", "\"Let's not talk about that.\"", "\"Stay out of it.\""]
const REL_COLD: Array[String] = ["\"Not a fan, honestly.\"", "\"We don't really get along.\"", "\"Could be better.\""]
const REL_NEUTRAL: Array[String] = ["\"They're alright, I guess.\"", "\"Can't say much either way.\"", "\"Haven't really thought about it.\""]
const REL_FRIENDLY: Array[String] = ["\"They're pretty cool.\"", "\"I like them.\"", "\"Good to have around.\""]
const REL_CLOSE: Array[String] = ["\"They're really cool!\"", "\"Honestly? One of my favorites here.\"", "\"I really like them.\""]

const RELAXING_REFUSAL: Array[String] = [
	"\"I'm relaxing right now.\"",
	"\"Can it wait? I'm on a break.\"",
	"\"Give me a minute, I'm resting.\"",
]

## Short floating one-liners (NPC.bark()). Event barks fire on things that
## happen; the greeting bark reuses greeting() when the player walks up.
const BARKS: Dictionary = {
	"thanks":        ["Thanks!", "Oh — thank you.", "You're a lifesaver.", "Appreciate it."],
	"thanks_friend": ["Thanks, %s.", "You didn't have to, %s.", "%s, you're the best."],
	"snatched":      ["Hey! That's mine!", "Give that back!", "Seriously?!"],
	"snatch_win":    ["Mine now.", "Finders keepers.", "Should've held on tighter."],
	"food_ready":    ["Food's ready!", "Soup's on!", "Hot meal, come and get it."],
	"woke":          ["*yawns*", "Morning...", "Mmh. Already?"],
	"woke_floor":    ["Ugh, my back...", "Never sleeping on concrete again."],
	"tidy":          ["There. Better.", "Why is there always junk everywhere..."],
	"hungry":        ["I'm starving...", "Need to find something to eat."],
	"thirsty":       ["So thirsty...", "Water. I need water."],
	"refuse_work":   ["Later.", "Can't be bothered right now.", "Do it yourself.", "Yeah, in a bit.", "Not now, I'm busy doing nothing.", "Why me?"],
	"strained":      ["I can't take much more of this.", "Something's gotta give down here.", "I'm hanging by a thread.", "How long can we keep living like this?"],
	"crash_hostile": ["That's IT. I'm DONE.", "I've had ENOUGH!", "You want to see me snap? Here it is!"],
	"crash_overdrive": ["No. No more. I'm fixing this. All of it.", "Nobody else is going to hold this place together.", "Move. I've got work to do."],
	"crash_breakdown": ["I can't... I can't do this anymore.", "Just... leave me alone.", "Why is this happening..."],
	"seething":      ["Unbelievable.", "Every. Single. Day.", "Don't talk to me.", "I swear..."],
	"sob":           ["*sobbing*", "I want to go home...", "*shaking*", "Make it stop..."],
	"sabotage":      ["There! Happy now?!", "Let it all fall apart!", "Who cares anymore?!"],
	## Violence (NPCCombat).
	"hurt":          ["Agh!", "Ow — what the hell?!", "Stop!", "Argh!"],
	"flee":          ["Get away from me!", "Help! Somebody!", "Don't — please!", "Stay back!"],
	"fight_back":    ["You want a fight? Fine!", "Big mistake.", "That's the last time you touch me!"],
	"horrified":     ["Oh my God...", "No, no, no...", "Is... is %s dead?", "%s?! No..."],
	"horrified_killing": ["What did you DO?!", "You killed %s!", "Oh my God... %s...", "No — no, no, no!"],
	## Someone they hated died: no grief, no gloating in front of the body.
	"death_enemy":   ["...Huh.", "Can't say I'll miss %s.", "Well. That's that.", "..."],
	"attack":        ["This ends NOW!", "You did this to us!", "I warned you!", "Come here!"],
	## Fights and their de-escalation (CrashOutActivity / NPCCombat).
	"brawl_start":   ["You want to go? Let's go!", "Come on then!", "I've had it with you, %s!", "Put 'em up!"],
	"grab_weapon":   ["Where is it — there.", "Fine. FINE.", "You asked for this."],
	"back_down":     ["Okay! Okay — I'm sorry!", "Whoa, whoa. I don't want to fight.", "Forget it. You win.", "I'm not doing this."],
	"stare_down":    ["That's what I thought.", "Yeah. Walk away.", "Coward."],
	"talk_down":     ["Hey. HEY. Not worth it.", "%s, stop. Look at me.", "Walk away. Come on.", "Don't. You'll regret it."],
	"talked_down":   ["...Fine. FINE.", "...You're right. You're right.", "Get out of my way, then.", "*breathes*"],
	"held_back":     ["Not again. Not today.", "...Forget it.", "I'm not doing this again."],
	"peacemaker_run": ["Hey! Break it up!", "Stop it! Both of you!", "Whoa — enough!"],
	"peacemaker_separate": ["ENOUGH!", "Back off! Back OFF!", "It's over. It's over!"],
	"pulled_off":    ["Get off me!", "Let go of me!", "This isn't over, %s!"],
	"beat_down":     ["Stay down.", "Don't get up.", "Had enough?"],
	"beaten":        ["Okay... okay... you win.", "Stop... please...", "*coughing*"],
	"done_fighting": ["Stay away from me.", "We're done here.", "Don't ever — ever — do that again."],
	"treat_self":    ["*hisses* Come on...", "Ow — okay, okay.", "This is going to sting.", "Hold it together..."],
	"treat_other":   ["Hold still.", "Let me see that.", "This'll sting.", "Easy. I've got you."],
	## Organizing (StorageProfile): why they walk past nearer storage, and
	## why they move something that's already put away.
	"organize_garden":    ["Seeds and soil go by the garden.", "Garden things stay by the garden.", "This belongs by the trays."],
	"organize_kitchen":   ["Fresh food goes by the kitchen.", "This belongs by the stove.", "Kitchen things stay in the kitchen."],
	"organize_stores":    ["Keeping the stores together.", "Supplies go with the supplies.", "All the stores in one place."],
	"organize_drawer":    ["Small things go in a drawer.", "This goes in a drawer, not on a shelf.", "Drawers are for the small stuff."],
	"organize_generator": ["Fuel lives by the generator.", "Fuel goes by the generator."],
	"organize_purifier":  ["Filters go by the purifier.", "Keeping the filters by the water."],
	"organize_same":      ["Keeping like with like.", "These go with the others."],
	## Before the seal (BunkerPhase preparation): an order to use supplies.
	"prep_refuse":   ["Not yet. That's for after we seal up.", "We're saving that for Day 1.", "Let's not touch the supplies yet."],
	## Neglect (NPCSocial._tick_neglect): days of it, said to the player's face.
	"neglect_light": ["How long are you going to leave us in the dark?", "Days in the dark. Days.", "Are you ever fixing the lights?"],
	"neglect_water": ["We can't keep drinking this.", "When's there going to be clean water?", "I'm sick of being thirsty."],
	"neglect_food":  ["We're starving down here. You know that, right?", "When did any of us last eat properly?", "Hungry again. Still."],
	"neglect_rest":  ["Another night on the floor.", "I can't remember the last time I slept properly.", "A bed. That's all I'm asking."],
	"keep_away":     ["Don't come any closer.", "I'm going, I'm going.", "Just... stay over there.", "Please. Not me."],
	"hide_run":      ["Get down! Everybody get down!", "They've got a weapon!", "Run! RUN!", "Oh God, oh God—"],
	"hide_cower":    ["Stay quiet... stay quiet...", "Is it over?", "Please let it be over.", "*breathing hard*"],
	"step_aside":    ["Whoa, whoa!", "Not my fight!", "Hey — watch it!"],
	"witness_shout": ["Hey! Stop it!", "Somebody stop them!", "What are you DOING?!", "Leave %s alone!"],
	"shun_work":     ["I'm not working next to %s.", "Not while %s is here.", "Keep %s away from me and I'll work."],
	"rescued_defended": ["You — you stopped them. Thank you.", "I thought I was dead. Thank you.", "You saved me."],
	"rescued_revived":  ["I... I'm still here?", "Thank you. I thought that was it.", "You kept me alive. I won't forget it."],
	"calmed_hostile":   ["...I'm sorry. I don't know what came over me.", "I lost it. I know I lost it.", "Okay. I'm okay now."],
	"calmed_breakdown": ["I'm alright. I think.", "Sorry. I just... couldn't.", "*wipes eyes*"],
	"calmed_overdrive": ["I need to sit down.", "What... what time is it?", "I think I overdid it."],
}

## Hostile crash-out rants, aimed at whoever they're furious at.
const RANT_AT_PLAYER: Array[String] = [
	"This is YOUR fault!", "You did this to us!", "You call this leading?!",
	"Look at this place! LOOK at it!", "I trusted you!", "You don't care about any of us!",
]
const RANT_AT_RESIDENT: Array[String] = [
	"I can't stand you, %s!", "Everything's worse with you around, %s!", "Stay away from me, %s!",
	"You think I didn't notice, %s?!", "I'm sick of you, %s!",
]

static func rant_line(npc: NPC, target_id: String) -> String:
	if target_id == "player":
		return _pick(RANT_AT_PLAYER)
	var who: String = npc.bonds.display_name(target_id)
	return _pick(RANT_AT_RESIDENT) % who

## Replies to the player's Talk choices (NPCSocial.talk). Keyed by outcome.
const TALK_REPLIES: Dictionary = {
	"check_in":       ["\"I'm alright. Thanks for asking.\"", "\"Hanging in there.\"", "\"Not bad, all things considered.\""],
	"check_in_low":   ["\"Honestly? Not great. ...Thanks for asking.\"", "\"It means a lot that you noticed.\"", "\"I've been better. It helps to talk.\""],
	"encourage_good": ["\"...Yeah. Yeah, you're right. We'll get through this.\"", "\"Thanks. I needed that.\""],
	"encourage_flat": ["\"Sure. If you say so.\"", "\"Easy for you to say.\""],
	"joke_good":      ["\"Ha! Okay, that was good.\"", "\"You're an idiot. ...That was funny though.\""],
	"joke_bad":       ["\"Really? Now?\"", "\"Not in the mood.\"", "\"...Was that supposed to be funny?\""],
	"vent_hard":      ["\"Right?! I thought it was just me.\"", "\"Finally, someone says it.\""],
	"vent":           ["\"Yeah, it's not perfect.\"", "\"Could be worse, I guess.\""],
	"insult":         ["\"Wow. Noted.\"", "\"You know what? Forget you.\"", "\"Say that again. I dare you.\""],
	"threaten":       ["\"...Okay. Okay. I'm going.\"", "\"Fine! FINE. I'm going.\"", "\"Alright, alright — I'm on it.\""],
	"encourage_lazy": ["\"Yeah, yeah. Sure.\"", "\"Mm. Nice speech.\"", "\"Thanks. ...So, anyway.\""],
	"firm_lazy":      ["\"Ugh. Fine.\"", "\"Alright, alright. Don't get your shorts in a twist.\"", "\"...Fine. Going.\""],
	"firm_worker":    ["\"I'm already on it.\"", "\"You don't need to tell me twice.\"", "\"Seriously? I never stop.\""],
	"promise":        ["\"You mean it? ...Alright. I'll hold you to that.\"", "\"I'll believe it when I see it.\""],
	"side":           ["\"Thank you. Seriously.\"", "\"Good to know someone's on my side.\""],
}

static func talk_reply(npc: NPC, outcome: String) -> String:
	var pool: Array = TALK_REPLIES.get(outcome, [])
	if pool.is_empty():
		return greeting(npc)
	return _pick(pool)

static func bark_line(kind: String, subject: String = "") -> String:
	var pool: Array = BARKS.get(kind, [])
	if pool.is_empty():
		return ""
	var line: String = _pick(pool)
	return line % subject if line.contains("%s") else line

## greeting() without the surrounding quote marks, for a floating bark as
## the player walks by. Only when it says something about their state:
## a plain "Hey." / "Need something?" isn't worth a bubble ("").
static func greeting_bark(npc: NPC) -> String:
	var line: String = greeting(npc)
	if NEUTRAL.has(line):
		return ""
	return line.trim_prefix("\"").trim_suffix("\"")

static func _pick(pool: Array) -> String:
	return String(pool[randi() % pool.size()])

## Strongest thought of `id` ({} if none) — for subject-bearing lines.
static func _thought(npc: NPC, id: String) -> Dictionary:
	if npc.thoughts == null:
		return {}
	for t: Dictionary in npc.thoughts.describe():
		if String(t["id"]) == id:
			return t
	return {}

## Fills "%s"; the player ("You") reads "you" unless it starts the line.
static func _sub(line: String, subject: String) -> String:
	if not line.contains("%s"):
		return line
	if subject == "You" and not (line.begins_with("%s") or line.begins_with("\"%s")):
		subject = "you"
	return line % subject

static func greeting(npc: NPC) -> String:
	## Mid crash-out: nothing else gets through.
	if npc.crash.active():
		if npc.crash.mode == NPCCrashOut.Mode.HOSTILE and npc.crash.target_id == "player":
			return _pick(TOWARD_PLAYER_FURIOUS)
		return _pick(CRASH_GREETING.get(npc.crash.mode_name(), NEUTRAL))
	var irr: String = npc.get_irritability_label()
	if irr == "Rage" or irr == "Mad":
		return _pick(ANGRY)
	## Fear of the player beats everything else they might say.
	if npc.social.fear >= 60.0:
		return _pick(TOWARD_PLAYER_AFRAID)
	var rel: String = npc.get_relationship_label("player")
	if rel == "Hostile":
		return _pick(TOWARD_PLAYER_HOSTILE)
	if npc.bonds.grudge_against("player") <= -20.0 and randf() < 0.6:
		return _pick(TOWARD_PLAYER_GRUDGE)
	var saved: Dictionary = _thought(npc, "saved_me")
	if not saved.is_empty() and String(saved["subject"]) == "You" and randf() < 0.7:
		return _pick(TOWARD_PLAYER_GRATEFUL)
	var grief: Dictionary = _thought(npc, "grieving")
	if not grief.is_empty() and randf() < 0.6:
		return "\"%s\"" % _sub(_pick(GRIEF).trim_prefix("\"").trim_suffix("\""), String(grief["subject"]))
	if npc.crash.daily_risk() > 0.0 and randf() < 0.6:
		return _pick(BREAKING_POINT)
	if npc.social.fear >= 30.0 and randf() < 0.5:
		return _pick(TOWARD_PLAYER_WARY)
	if irr == "Frustrated":
		return _pick(FRUSTRATED)
	if npc.hunger < 20.0:
		return _pick(HUNGRY)
	if npc.thirst < 20.0:
		return _pick(THIRSTY)
	if npc.energy < 15.0:
		return _pick(EXHAUSTED)
	if rel == "Cold" and randf() < 0.6:
		return _pick(TOWARD_PLAYER_COLD)
	if irr == "Grumpy" and randf() < 0.6:
		return _pick(GRUMPY)
	if npc.thoughts != null and randf() < ON_MIND_CHANCE:
		var t: Dictionary = npc.thoughts.strongest(npc.mood >= 50.0)
		if t.is_empty():
			t = npc.thoughts.strongest(npc.mood < 50.0)
		if not t.is_empty() and absf(float(t["mood"])) >= 1.5 and ON_MIND.has(t["id"]):
			return _sub(_pick(ON_MIND[t["id"]]), String(t["subject"]))
	## What's wearing them down (or lifting them up) about the bunker.
	var reasons: Array[Dictionary] = npc.morale_sys.get_reasons()
	if not reasons.is_empty() and randf() < 0.5:
		var top: Dictionary = reasons[0]
		var pool: Dictionary = CONDITION_BAD if float(top["points"]) < 0.0 else CONDITION_GOOD
		if pool.has(String(top["id"])) and (npc.mood < 50.0) == (float(top["points"]) < 0.0):
			return _pick(pool[String(top["id"])])
	if rel == "Close" and randf() < 0.5:
		return _pick(TOWARD_PLAYER_CLOSE)
	if npc.mood < 25.0:
		return _pick(LOW_MOOD)
	if npc.mood >= 75.0:
		return _pick(HAPPY)
	return _pick(NEUTRAL)

static func about(npc: NPC, target_id: String) -> String:
	match npc.get_relationship_label(target_id):
		"Hostile": return _pick(REL_HOSTILE)
		"Cold": return _pick(REL_COLD)
		"Friendly": return _pick(REL_FRIENDLY)
		"Close": return _pick(REL_CLOSE)
	return _pick(REL_NEUTRAL)

static func relaxing_refusal() -> String:
	return _pick(RELAXING_REFUSAL)
