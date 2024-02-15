import React, { useCallback, useState } from "react";

import { map } from "./utils.js";
import "./api.js";

const ranges = {
	attraction: [0.00005, 0.002],
	repulsion: [50, 200],
	temperature: [0.005, 0.5],
} as const;

const scale = {
	attraction: {
		to: (value: number) => map(0, 100, ...ranges.attraction, value),
		from: (value: number) => map(...ranges.attraction, 0, 100, value),
	},
	repulsion: {
		to: (value: number) => map(0, 100, ...ranges.repulsion, value),
		from: (value: number) => map(...ranges.repulsion, 0, 100, value),
	},
	temperature: {
		to: (value: number) => map(0, 100, ...ranges.temperature, value),
		from: (value: number) => map(...ranges.temperature, 0, 100, value),
	},
};

export interface ControlPanelProps {
	onReset?: () => void;
}

export const ControlPanel: React.FC<ControlPanelProps> = (props) => {
	const [attraction, setAttractionScale] = useState(() => scale.attraction.from(window.attraction));

	const [repulsion, setRepulsionScale] = useState(() => scale.repulsion.from(window.repulsion));

	const [temperature, setTemperatureScale] = useState(() => scale.temperature.from(window.temperature));

	const handleAttractionChange = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
		const attraction = event.target.valueAsNumber;
		setAttractionScale(attraction);
		window.env.setAttraction(scale.attraction.to(attraction));
	}, []);

	const handleRepulsionChange = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
		const repulsion = event.target.valueAsNumber;
		setRepulsionScale(repulsion);
		window.env.setRepulsion(scale.repulsion.to(repulsion));
	}, []);

	const handleTemperatureChange = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
		const temperature = event.target.valueAsNumber;
		setTemperatureScale(temperature);
		window.env.setTemperature(scale.temperature.to(temperature));
	}, []);

	return (
		<div style={{ display: "flex", flexDirection: "column", alignItems: "end" }}>
			<div>
				<label>Attraction: </label>
				<input type="range" min="0" max="100" step="1" value={attraction} onChange={handleAttractionChange} />
			</div>
			<code>{scale.attraction.to(attraction).toPrecision(4)}</code>
			<div>
				<label>Repulsion: </label>
				<input type="range" min="0" max="100" step="1" value={repulsion} onChange={handleRepulsionChange} />
			</div>
			<code>{scale.repulsion.to(repulsion).toPrecision(4)}</code>
			<div>
				<label>Temperature: </label>
				<input type="range" min="0" max="100" step="1" value={temperature} onChange={handleTemperatureChange} />
			</div>
			<code>{scale.attraction.to(temperature).toPrecision(4)}</code>
			<div style={{ marginTop: "1em", display: "flex", gap: "1em" }}>
				<button onClick={props.onReset}>Reset</button>
				{/* <button onClick={() => window.env.tick()}>Tick</button> */}
				<button onClick={() => window.env.save()}>Save</button>
			</div>
			<div style={{ marginTop: "1em", marginBottom: "0.5em", display: "flex", gap: "1em" }}>
				<button onClick={() => window.env.start()}>Start</button>
				<button onClick={() => window.env.stop()}>Stop</button>
			</div>
		</div>
	);
};
