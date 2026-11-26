export interface EmojiCategory {
  id: string;
  icon: string;
  values: string[];
}

// A subset of the Unicode emoji groups, through Emoji 13.0.
// Each space-separated entry is one grapheme. Keep the presentation selectors.
export const EMOJI_CATEGORIES: EmojiCategory[] = [
  { id: 'recent', icon: '🕒', values: [] },
  { id: 'faces', icon: '😀', values: (
    '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 ☺️ 🥲 ' +
    '😋 😜 🤪 🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 🙄 😬 😌 😔 😴 ' +
    '😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 🤯 🤠 🥳 🥸 😎 🤓 🧐 😕 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 ' +
    '😨 😥 😢 😭 😱 😖 😞 😩 😤 😡 🤬 😈 💀 ☠️ 💩 🤡 👹 👻 ' +
    '👽 👾 🤖 😺 😹 😻 🙀'
  ).split(' ') },
  { id: 'people', icon: '👋', values: (
    '👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 ' +
    '🤝 🙏 ✍️ 💅 🤳 💪 🦵 🦶 👂 👃 🧠 🦷 👀 👅 👄 👶 🧒 👦 👧 🧑 👨 👩 👴 👵 ' +
    '🙅 🙆 💁 🙋 🙇 🤦 🤷 👮 🥷 👷 🤴 👸 🤰 👼 ' +
    '🎅 🦸 🧙 🧚 🧟 🚶 🧍 🏃 💃 🕺 🗣️ 🫂'
  ).split(' ') },
  { id: 'nature', icon: '🐱', values: (
    '🙈 🙉 🙊 🐵 🦍 🐶 🐕 🐩 🐺 🦊 🦝 🐱 🐈 🦁 🐯 🐴 🐎 🦄 🦓 🦌 ' +
    '🐮 🐄 🐷 🐑 🐫 🦙 🦒 🐘 🦣 🦛 🐭 🐹 🐰 🐿️ 🦔 🦇 ' +
    '🐻 🐨 🐼 🦥 🐾 🐔 🐣 🐦 🐧 🕊️ 🦉 🦩 🐸 🐢 🐍 ' +
    '🐉 🦖 🐳 🐬 🦭 🐟 🦈 🐙 🐚 🐌 🦋 🐝 🐞 🕷️ 🌺 🌻 🌹 🌷 🌸 💐 ' +
    '🌱 🌲 🌳 🌴 🌵 🌿 ☘️ 🍀 🍁 🍂'
  ).split(' ') },
  { id: 'food', icon: '🍎', values: (
    '🍇 🍈 🍉 🍊 🍋 🍌 🍍 🥭 🍎 🍐 🍑 🍒 🍓 🫐 🥝 🍅 🥑 🍆 🥕 🌽 🌶️ 🥒 🥦 ' +
    '🧄 🍄 🌰 🍞 🥐 🥞 🧀 🍖 🍗 🥩 🍔 🍟 🍕 🌭 🥪 🌮 🥚 🍳 ' +
    '🍲 🫕 🥗 🍿 🍱 🍙 🍛 🍜 🍝 🍢 🍣 🍤 🍡 🥟 🦀 🦐 🍦 🍧 ' +
    '🍩 🍪 🎂 🍰 🍫 🍬 🍮 🥛 ☕ 🫖 🍵 🍶 🍷 🍸 🍺 🍻 🧃 🧋'
  ).split(' ') },
  { id: 'travel', icon: '✈️', values: (
    '🌍 🌎 🌏 🌐 🗺️ 🗾 🏔️ 🌋 🗻 🏕️ 🏖️ 🏝️ 🏟️ 🏠 🏢 🏥 🏫 🏯 🏰 ' +
    '🗼 🗽 ⛪ ⛩️ ⛺ 🌃 🌅 🌉 🚂 🚅 🚇 🚌 🚑 🚒 🚓 🚕 🚗 🚚 ' +
    '🏍️ 🚲 🛴 ⛽ 🚦 🚧 ⚓ ⛵ 🚢 ✈️ 🛫 🚁 🚀 🛰️ 🌑 🌓 🌕 🌙 ' +
    '☀️ 🪐 ⭐ 🌟 🌌 ☁️ ⛅ ⛈️ 🌧️ 🌪️ 🌈 ☔ ⚡ ❄️ ⛄ 🔥 💧 🌊'
  ).split(' ') },
  { id: 'activities', icon: '⚽', values: (
    '🎃 🎄 🎆 🎇 ✨ 🎈 🎉 🎊 🎋 🎍 🎎 🎏 🎐 🎑 🎀 🎁 🎫 🏆 🏅 🥇 🥈 🥉 ' +
    '⚽ ⚾ 🏀 🏐 🏈 🏉 🎾 🎳 🏓 🏸 🥊 🥋 ⛳ ⛸️ 🎣 🤿 🎿 🥌 ' +
    '🎯 🪁 🎱 🔮 🪄 🎮 🎰 🎲 🧩 🧸 ♠️ ♥️ ♦️ ♣️ 🃏 🀄 🎴 🎭 🖼️ 🎨 🧵 🧶'
  ).split(' ') },
  { id: 'objects', icon: '💡', values: (
    '👓 🕶️ 👔 👕 👖 🧣 🧤 👗 👘 👜 🎒 👟 👑 🎩 🎓 💄 💍 💎 ' +
    '🔊 📢 🔔 🎵 🎤 🎧 📻 🎸 🎹 🎺 🎻 🥁 📱 ☎️ 🔋 🔌 💻 ⌨️ ' +
    '💿 🎥 🎬 📺 📷 🔍 🕯️ 💡 🔦 📚 📖 📄 📰 🔖 💰 🪙 💴 💵 💳 ✉️ 📧 📦 📮 ' +
    '✏️ 📝 📅 📌 📎 ✂️ 🔒 🔑 🔨 🔧 ⚙️ 💊 🚪 🛏️ 🚽 🚿 🛒'
  ).split(' ') },
  { id: 'symbols', icon: '❤️', values: (
    '💋 💌 💘 💖 💕 💔 ❤️ 🧡 💛 💚 💙 💜 🤎 🖤 🤍 💯 💢 💥 💬 💤 ' +
    '♿ 🚻 ⚠️ ⛔ 🚫 🚭 🔞 ⬆️ ➡️ ⬇️ ⬅️ ↔️ 🔄 ' +
    '☯️ ✝️ ☪️ ⏩ ⏪ ⏸️ ⏹️ ✖️ ➕ ➖ ➗ ' +
    '❓ ❗ ‼️ ⁉️ ♻️ ✅ ❌ ©️ ®️ ™️ #️⃣ *️⃣ 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 ' +
    '🔴 🟠 🟡 🟢 🔵 🟣 🟤 ⚫ ⚪'
  ).split(' ') },
  { id: 'flags', icon: '🇯🇵', values: (
    '🇯🇵 🇰🇷 🇨🇳 🇹🇼 🇭🇰 🇮🇳 🇮🇩 🇹🇭 🇻🇳 🇸🇬 🇲🇾 🇵🇭 🇦🇺 🇳🇿 🇺🇸 🇨🇦 🇲🇽 🇧🇷 🇦🇷 ' +
    '🇬🇧 🇫🇷 🇩🇪 🇮🇹 🇪🇸 🇵🇹 🇳🇱 🇧🇪 🇨🇭 🇸🇪 🇺🇦 🇷🇺 🇹🇷 🇸🇦 🇦🇪 🇪🇬 🇿🇦'
  ).split(' ') }
];

const availableEmoji: Set<string> = new Set<string>();
for (const category of EMOJI_CATEGORIES) {
  for (const value of category.values) { availableEmoji.add(value); }
}

export function isPanelEmoji(value: string): boolean { return availableEmoji.has(value); }
