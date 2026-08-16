const chatMessages = document.getElementById("chat-messages");
const chatForm = document.getElementById("chat-form");
const chatInput = document.getElementById("chat-input");
const launchModal = document.getElementById("launch-modal");

const DEMO_RESPONSES = [
  { type: "tool", text: "glob **/*.{html,css,js,tsx}" },
  { type: "tool", text: "read README.md, package.json" },
  { type: "agent", text: "Creating web/ front end with hero, features, and agent playground demo." },
  { type: "tool", text: "write web/index.html, web/css/style.css, web/js/app.js" },
  { type: "tool", text: "edit package.json — add \"web\" script" },
  { type: "agent", text: "Done. Run npm run web and open http://localhost:5173/web" },
];

function appendMessage(text, className) {
  const el = document.createElement("div");
  el.className = `msg ${className}`;
  el.textContent = text;
  chatMessages.appendChild(el);
  chatMessages.scrollTop = chatMessages.scrollHeight;
  return el;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runAgentDemo(userText) {
  appendMessage(userText, "msg-user");
  chatInput.disabled = true;

  for (const step of DEMO_RESPONSES) {
    await delay(600 + Math.random() * 400);
    const cls = step.type === "tool" ? "msg-tool" : "msg-agent";
    const prefix = step.type === "tool" ? "▸ " : "";
    appendMessage(prefix + step.text, cls);
  }

  chatInput.disabled = false;
  chatInput.focus();
}

function seedWelcome() {
  appendMessage(
    "Agent mode active — I will explore the repo and implement without asking clarifying questions.",
    "msg-agent",
  );
}

chatForm.addEventListener("submit", (e) => {
  e.preventDefault();
  const text = chatInput.value.trim();
  if (!text) return;
  chatInput.value = "";
  void runAgentDemo(text);
});

document.getElementById("btn-launch-info").addEventListener("click", () => {
  launchModal.showModal();
});

document.getElementById("btn-open-playground").addEventListener("click", () => {
  document.getElementById("playground").scrollIntoView({ behavior: "smooth" });
  chatInput.focus();
});

document.getElementById("modal-close").addEventListener("click", () => {
  launchModal.close();
});

document.getElementById("copy-launch").addEventListener("click", async () => {
  const cmd = document.getElementById("launch-cmd").textContent;
  try {
    await navigator.clipboard.writeText(cmd);
    document.getElementById("copy-launch").textContent = "Copied!";
    setTimeout(() => {
      document.getElementById("copy-launch").textContent = "Copy command";
    }, 2000);
  } catch {
    document.getElementById("copy-launch").textContent = "Copy failed";
  }
});

seedWelcome();
