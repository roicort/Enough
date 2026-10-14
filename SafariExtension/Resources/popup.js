const clearCacheButton = document.querySelector("#clear-cache");
const cacheCount = document.querySelector("#cache-count");
const status = document.querySelector("#status");
const threshold = document.querySelector("#threshold");
const showVerifiedAI = document.querySelector("#show-verified-ai");

async function request(action) {
  const response = await browser.runtime.sendMessage({ action });
  if (!response || response.error) {
    throw new Error(response?.error || "Unable to update extension status.");
  }
  return response.data;
}

function setCacheCount(count) {
  cacheCount.textContent = String(count);
}

async function loadState() {
  try {
    const state = await request("popupState");
    if (typeof state.aiConfidenceThreshold === "number") {
      threshold.textContent = new Intl.NumberFormat("en", {
        style: "percent",
        maximumFractionDigits: 0
      }).format(state.aiConfidenceThreshold);
    } else {
      threshold.textContent = "Unavailable";
    }
    showVerifiedAI.textContent = typeof state.showVerifiedAIC2PA === "boolean"
      ? (state.showVerifiedAIC2PA ? "On" : "Off")
      : "Unavailable";
    if (typeof state.cachedAnalyses === "number") {
      setCacheCount(state.cachedAnalyses);
    } else {
      cacheCount.textContent = "Unavailable";
    }
    status.textContent = state.settingsError || state.cacheError || "";
  } catch (error) {
    threshold.textContent = "Unavailable";
    showVerifiedAI.textContent = "Unavailable";
    cacheCount.textContent = "Unavailable";
    status.textContent = error.message;
  }
}

clearCacheButton.addEventListener("click", async () => {
  clearCacheButton.disabled = true;
  status.textContent = "Clearing cache...";
  try {
    const result = await request("clearAnalysisCache");
    setCacheCount(result.cachedAnalyses);
    status.textContent = "Analysis cache cleared.";
  } catch (error) {
    status.textContent = error.message;
  } finally {
    clearCacheButton.disabled = false;
  }
});

loadState();
