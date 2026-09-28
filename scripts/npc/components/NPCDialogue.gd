extends RefCounted
class_name NPCDialogue
## NPCDialogue.gd (Sep 2026; pools formerly inline in NPC.gd).
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
	"\"What's up?\"",
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
	"good_chat":         ["\"Had a good talk with %s earlier.\"", "\"%s is alright, you know?\""],
	"bad_chat":          ["\"%s and I got into it earlier. Don't ask.\"", "\"If %s says one more thing to me...\""],
	"received_gift":     ["\"%s brought me something earlier. Good people.\""],
	"helped_friend":     ["\"Made sure %s got something to eat. We look out for each other.\""],
	"got_snatched":      ["\"%s snatched my food right out of my hands.\"", "\"Watch %s. They'll take the food out of your mouth.\""],
	"food_taken":        ["\"Someone took my food while I was eating. Who does that?\""],
	"relaxed":           ["\"Took a proper break. Needed that.\""],
	"break_interrupted": ["\"I was on a break, you know.\""],
	"productive":        ["\"Got a lot done today. Feels good.\""],
	"cluttered":         ["\"This place is a mess. Someone should tidy up.\"", "\"I keep tripping over junk down here.\""],
	"in_pain":           ["\"Everything hurts.\"", "\"I'm not in great shape right now.\""],
	"lonely":            ["\"Feels like nobody talks to each other down here.\""],
	"crowded_beds":      ["\"Would be nice to have a bed I could count on.\""],
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
}

## Conversation snippets (TalkActivity turn-taking). About half the time a
## resident brings up something real (their strongest thought, phrased for
## a peer); otherwise bunker small talk, tinted by mood.
const SMALL_TALK: Array[String] = [
	"How are you holding up?", "Sleep okay?", "Think anyone's still up there?",
	"I keep hearing the pipes at night.", "How long do you think the food will last?",
	"We should fix up this place a bit.", "Heard anything on the radio?",
	"I miss the sun.", "What day is it even?", "You doing alright?",
	"Remember fresh coffee?", "We're going to make it. Probably.",
]
const SMALL_TALK_GLUM: Array[String] = [
	"I don't know how much longer I can do this.", "Everything's so grey down here.",
	"Some days I just... ugh.", "Don't you ever get tired of it?",
]
const SMALL_TALK_REPLY: Array[String] = [
	"Yeah.", "Tell me about it.", "Ha, right?", "Mm-hm.", "Same.", "Don't remind me.",
	"Could be worse.", "True.", "No kidding.",
]
const CHAT_ABOUT: Dictionary = {
	"ate_hot_meal": ["That hot meal earlier was amazing.", "Someone actually cooked today!"],
	"ate_cold_can": ["If I eat one more cold can...", "Canned again. Of course."],
	"slept_in_bed": ["Actually slept well last night.", "Beds. Underrated."],
	"slept_on_floor": ["My back is wrecked. Floor again.", "We need more beds."],
	"slept_in_chair": ["Fell asleep in a chair. Big mistake."],
	"collapsed": ["I literally passed out yesterday.", "Pushed myself too hard."],
	"got_snatched": ["%s took my food. Just took it.", "Watch out for %s."],
	"received_gift": ["%s brought me food earlier. Sweet of them."],
	"bad_chat": ["%s and I aren't talking right now."],
	"good_chat": ["%s is good company, you know?"],
	"cluttered": ["This place is a mess.", "Somebody should really tidy up."],
	"in_pain": ["Everything hurts today.", "Can't shake this injury."],
	"lonely": ["Feels like nobody talks down here.", "Nice to actually talk to someone."],
	"productive": ["Got a lot done today.", "Keeping busy helps."],
	"relaxed": ["Took a proper break. Needed it."],
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

static func chat_line(npc: NPC, replying: bool) -> String:
	if replying and randf() < 0.45:
		return _pick(SMALL_TALK_REPLY)
	if npc.thoughts != null and randf() < 0.5:
		var t: Dictionary = npc.thoughts.strongest(randf() < 0.5)
		if not t.is_empty() and CHAT_ABOUT.has(t["id"]):
			var line: String = _pick(CHAT_ABOUT[t["id"]])
			return line % String(t["subject"]) if line.contains("%s") else line
	return _pick(SMALL_TALK_GLUM if npc.mood < 35.0 else SMALL_TALK)

static func bark_line(kind: String, subject: String = "") -> String:
	var pool: Array = BARKS.get(kind, [])
	if pool.is_empty():
		return ""
	var line: String = _pick(pool)
	return line % subject if line.contains("%s") else line

## greeting() without the surrounding quote marks, for a floating bark.
static func greeting_bark(npc: NPC) -> String:
	return greeting(npc).trim_prefix("\"").trim_suffix("\"")

static func _pick(pool: Array) -> String:
	return String(pool[randi() % pool.size()])

static func greeting(npc: NPC) -> String:
	var irr: String = npc.get_irritability_label()
	if irr == "Rage" or irr == "Mad":
		return _pick(ANGRY)
	var rel: String = npc.get_relationship_label("player")
	if rel == "Hostile":
		return _pick(TOWARD_PLAYER_HOSTILE)
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
			var line: String = _pick(ON_MIND[t["id"]])
			return line % String(t["subject"]) if line.contains("%s") else line
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
