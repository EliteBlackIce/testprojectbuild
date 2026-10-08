class_name StaffData
extends RefCounted
## Eggs you can hire from Tony's PC. Cooks make pizzas start to finish
## (dough -> sauce -> oven -> cut -> box -> pass shelf). Phone eggs answer calls.
## Everyone has a quirk. Wages come out of your money at closing time.

const CANDIDATES := {
	"larry": {"name": "Lazy Larry", "role": "cook", "skill": 0.55, "wage": 12, "hire": 60, "quirk": "naps",
		"pitch": "Will make pizza. Will also nap on the job. Cheap!",
		"look": {"skin": "#e8c39e", "hat": "beanie", "hat_color": "#6c5ce7", "stretch": 0.92, "round": 1.15, "belly": 0.18, "apron": "#f6f4ef"}},
	"carla": {"name": "Clumsy Carla", "role": "cook", "skill": 0.62, "wage": 15, "hire": 90, "quirk": "drops",
		"pitch": "Fast hands, slippery hands. Spills sauce on the floor. Watch your step.",
		"look": {"skin": "#f3d2b3", "hat": "bow", "hat_color": "#ff7eb6", "glasses": true, "stretch": 1.05, "apron": "#f6f4ef"}},
	"steve": {"name": "Snacky Steve", "role": "cook", "skill": 0.7, "wage": 18, "hire": 120, "quirk": "snacks",
		"pitch": "Good cook. Eats toppings. Sometimes the pepperoni just... disappears.",
		"look": {"skin": "#d7a37a", "hat": "chef", "hat_color": "#f6f4ef", "belly": 0.24, "round": 1.2, "mustache": true, "apron": "#f6f4ef"}},
	"gonzalegg": {"name": "Speedy Gonzalegg", "role": "cook", "skill": 0.78, "wage": 26, "hire": 200, "quirk": "fast",
		"pitch": "Runs everywhere. Everywhere. Occasionally into walls.",
		"look": {"skin": "#c98f5e", "hat": "headband", "hat_color": "#e63946", "stretch": 1.15, "round": 0.9, "apron": "#f6f4ef"}},
	"yolanda": {"name": "Nonna Yolanda", "role": "cook", "skill": 0.95, "wage": 40, "hire": 380, "quirk": "perfect",
		"pitch": "Has made pizza since 1952. Slow, perfect, judges you silently.",
		"look": {"skin": "#f0d5bd", "hat": "bun", "hair_color": "#dfe6e9", "glasses": true, "stretch": 0.88, "round": 1.1, "apron": "#e74c3c", "blush": true}},
	"pam": {"name": "Pam the Phone Egg", "role": "phone", "skill": 0.9, "wage": 14, "hire": 80, "quirk": "polite",
		"pitch": "Answers every call in a perfect customer-service voice. Writes the ticket for you.",
		"look": {"skin": "#f5cba7", "hat": "headset", "hat_color": "#2d3436", "glasses": true, "tie": "#0984e3"}},
	"barry": {"name": "Gary's Cousin Barry", "role": "phone", "skill": 0.6, "wage": 7, "hire": 30, "quirk": "rude",
		"pitch": "Answers the phone. Sometimes hangs up on people for 'having a weird voice'.",
		"look": {"skin": "#e0ac69", "hat": "cap", "hat_color": "#27ae60", "hat_front": "#f6f4ef", "grumpy": true, "beard": true}},
}

const TRAIN_COST := 60          ## per training level
const TRAIN_MAX := 3
const TRAIN_BONUS := 0.08       ## skill per training level


static func skill_of(id: String, training: int) -> float:
	return clampf(float(CANDIDATES[id].skill) + training * TRAIN_BONUS, 0.0, 1.0)
