import React from "react";
import { createRoot } from "react-dom/client";

import { App } from "./App.js";
import "./api.js";

const main = document.querySelector("main");

if (main === null) {
	throw new Error("missing main element");
}

console.log(`attraction: ${window.attraction}`);
console.log(`repulsion: ${window.repulsion}`);
console.log(`temperature: ${window.temperature}`);
createRoot(main).render(<App />);
