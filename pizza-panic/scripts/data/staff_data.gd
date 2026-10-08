class_name StaffData
extends RefCounted
## Eggs you can hire from Tony's PC. Cooks make pizzas start to finish
## (dough -> sauce -> oven -> cut -> box -> pass shelf). Phone eggs answer calls.
## Everyone has a quirk. Wages come out of your money at closing time.

const CANDIDATES := {
	"larry": {"name": "Lazy Larry", "role": "cook", "skill": 0.55, "wage": 12, "hire": 60, "quirk": "naps",
		"pitch": "Will make pizza. Will also nap on the job. Cheap!",
		"look": {"skin": "#e8c39e", "hat": "beanie", "hat_color": "#6c5ce7", "round": 1.15, "belly": 0.18, "shirt": "#9aa5b1", "sleeves": "short", "apron": "#f6f4ef", "pants": "#6c6f7f", "shoes": "#c9c9d6"}},
	"carla": {"name": "Clumsy Carla", "role": "cook", "skill": 0.62, "wage": 15, "hire": 90, "quirk": "drops",
		"pitch": "Fast hands, slippery hands. Spills sauce on the floor. Watch your step.",
		"look": {"skin": "#f3d2b3", "hat": "bow", "hat_color": "#ff7eb6", "glasses": true, "hair": "#6b3e26", "hair_style": "cap", "shirt": "#ff9ec4", "sleeves": "short", "apron": "#f6f4ef", "pants": "#4b5ea6", "shoes": "#ff7eb6"}},
	"steve": {"name": "Snacky Steve", "role": "cook", "skill": 0.7, "wage": 18, "hire": 120, "quirk": "snacks",
		"pitch": "Good cook. Eats toppings. Sometimes the pepperoni just... disappears.",
		"look": {"skin": "#d7a37a", "hat": "chef", "hat_color": "#f6f4ef", "round": 1.2, "belly": 0.24, "mustache": true, "hair_color": "#3b2a1c", "shirt": "#ffffff", "sleeves": "long", "cuffs": "#ece4d4", "buttons": "#b8bcc6", "pants": "#3a3a45", "shoes": "#2d3436"}},
	"gonzalegg": {"name": "Speedy Gonzalegg", "role": "cook", "skill": 0.78, "wage": 26, "hire": 200, "quirk": "fast",
		"pitch": "Runs everywhere. Everywhere. Occasionally into walls.",
		"look": {"skin": "#c98f5e", "hat": "headband", "hat_color": "#e63946", "stretch": 1.1, "shirt": "#e63946", "sleeves": "long", "cuffs": "#ffffff", "stripe": "#ffffff", "shorts": true, "pants": "#ffffff", "socks": "#e63946", "shoes": "#ffffff", "shoe_trim": "#e63946"}},
	"yolanda": {"name": "Nonna Yolanda", "role": "cook", "skill": 0.95, "wage": 40, "hire": 380, "quirk": "perfect",
		"pitch": "Has made pizza since 1952. Slow, perfect, judges you silently.",
		"look": {"skin": "#f0d5bd", "hat": "bun", "hair_color": "#dfe6e9", "glasses": true, "blush": true, "shirt": "#fff3df", "sleeves": "long", "dress": "#c0392b", "apron": "#fff3df", "socks": "#f6f4ef", "shoes": "#6b4a35", "round": 1.1}},
	"pam": {"name": "Pam the Phone Egg", "role": "phone", "skill": 0.9, "wage": 14, "hire": 80, "quirk": "polite",
		"pitch": "Answers every call in a perfect customer-service voice. Writes the ticket for you.",
		"look": {"skin": "#f5cba7", "hat": "headset", "hat_color": "#2d3436", "glasses": true, "shirt": "#74b9ff", "sleeves": "short", "collar": "#ffffff", "tie": "#0984e3", "pants": "#2d3436", "shoes": "#2d3436"}},
	"barry": {"name": "Gary's Cousin Barry", "role": "phone", "skill": 0.6, "wage": 7, "hire": 30, "quirk": "rude",
		"pitch": "Answers the phone. Sometimes hangs up on people for 'having a weird voice'.",
		"look": {"skin": "#e0ac69", "hat": "cap", "hat_color": "#27ae60", "hat_front": "#f6f4ef", "grumpy": true, "beard": true, "hair_color": "#3b2a1c", "shirt": "#27ae60", "sleeves": "short", "collar": "#f6f4ef", "pants": "#6c5b3a", "shoes": "#3b2a1c"}},
}

const TRAIN_COST := 60          ## per training level
const TRAIN_MAX := 3
const TRAIN_BONUS := 0.08       ## skill per training level


static func skill_of(id: String, training: int) -> float:
	return clampf(float(CANDIDATES[id].skill) + training * TRAIN_BONUS, 0.0, 1.0)
