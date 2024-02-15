import "./api.js";

import { map } from "./utils.js";

// const minRadius = 1;
const minRadius = 0.5;

export function getMinZ(scale: number) {
	const mass = map(3, 50, 0, 80, minRadius / scale);
	if (mass < 0) {
		return 0;
	} else {
		return Math.pow(mass, 2);
	}
}

export function getRadius(scale: number, z: number) {
	return scale * map(0, 80, 3, 50, Math.sqrt(z));
}

function project(
	[x, y]: [number, number],
	offsetX: number,
	offsetY: number,
	scale: number,
	width: number,
	height: number
): [number, number] {
	return [(x + offsetX) * scale + width / 2, (y + offsetY) * scale + height / 2];
}

export function render(
	canvas: HTMLCanvasElement,
	offsetX: number,
	offsetY: number,
	scale: number,
	width: number,
	height: number,
	ids: Uint32Array
) {
	const ctx = canvas.getContext("2d");
	if (ctx === null) {
		throw new Error("failed to get drawing context");
	}

	ctx.clearRect(0, 0, width, height);

	// ctx.strokeStyle = "#888888";
	// for (let i = 0; i < edge_count; i++) {
	// 	const s = source[i] - 1;
	// 	const t = target[i] - 1;

	// 	const source_x = project(window.x[s], offsetX, scale);
	// 	const source_y = project(window.y[s], offsetY, scale);

	// 	const target_x = project(window.x[t], offsetX, scale);
	// 	const target_y = project(window.y[t], offsetY, scale);

	// 	ctx.beginPath();
	// 	ctx.moveTo(source_x, source_y);
	// 	ctx.lineTo(target_x, target_y);
	// 	ctx.stroke();
	// }

	ctx.fillStyle = "#222222";
	let n = 0;
	for (const idx of ids) {
		const i = idx - 1;
		const r = getRadius(scale, window.z[i]);

		const [node_x, node_y] = project([window.x[i], window.y[i]], offsetX, offsetY, scale, width, height);

		// if (r < 2) {
		// 	ctx.rect(node_x - r, node_y - r, r * 2, r * 2);
		// 	ctx.fill();
		// } else {
		ctx.beginPath();
		ctx.arc(node_x, node_y, r, 0, 2 * Math.PI);
		ctx.fill();
		ctx.closePath();
		// }

		n += 1;
	}
}
