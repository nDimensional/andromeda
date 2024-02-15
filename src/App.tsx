import React, { useCallback, useEffect, useRef, useState } from "react";

import { Canvas } from "./Canvas.js";
import { ControlPanel } from "./ControlPanel.js";

export const App: React.FC<{}> = ({}) => {
	const [offsetX, setOffsetX] = useState(0);
	const [offsetY, setOffsetY] = useState(0);
	const [zoom, setZoom] = useState(0);

	const handleReset = useCallback(() => {
		setOffsetX(0);
		setOffsetY(0);
		setZoom(0);
	}, []);

	const [width, setWidth] = useState(0);
	const [height, setHeight] = useState(0);

	const containerRef = useRef<HTMLDivElement | null>(null);
	useEffect(() => {
		if (containerRef.current === null) {
			return;
		}

		const observer = new ResizeObserver((entries) => {
			for (const entry of entries) {
				const { width, height } = entry.contentRect;
				setWidth(width);
				setHeight(height);
			}
		});

		observer.observe(containerRef.current);
	}, []);

	return (
		<div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "row", gap: 8 }}>
			<div style={{ padding: "1em 0.5em" }}>
				<ControlPanel onReset={handleReset} />
				<hr />
				<div style={{ textAlign: "end" }}>
					<code>
						{offsetX.toFixed(0)}, {offsetY.toFixed(0)}, {zoom}
					</code>
				</div>
			</div>

			<div ref={containerRef} style={{ flex: 1, overflowX: "hidden", overflowY: "hidden" }}>
				<Canvas
					width={width}
					height={height}
					offsetX={offsetX}
					setOffsetX={setOffsetX}
					offsetY={offsetY}
					setOffsetY={setOffsetY}
					zoom={zoom}
					setZoom={setZoom}
				/>
			</div>
		</div>
	);
};
