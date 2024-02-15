declare global {
	var env: Environment;

	var attraction: number;
	var repulsion: number;
	var temperature: number;

	var node_count: number;
	var edge_count: number;
	var x: Float32Array;
	var y: Float32Array;
	var z: Float32Array;
	var source: Uint32Array;
	var target: Uint32Array;
}

declare class Environment {
	refresh(minX: number, maxX: number, minY: number, maxY: number, minZ: number): Uint32Array;
	// tick(): void;
	save(): void;
	start(): void;
	stop(): void;
	setAttraction(value: number): void;
	setRepulsion(value: number): void;
	setTemperature(value: number): void;
}
