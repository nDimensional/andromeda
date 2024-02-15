import React, { useRef, useEffect, useCallback } from "react";
import { useDebouncedCallback } from "use-debounce";

import { getMinZ, render } from "./render.js";
import "./api.js";

const MIN_ZOOM = 0;
const MAX_ZOOM = 2400;
// const MAX_ZOOM = 4000;

function getScale(zoom: number) {
	return 0.00000010125 * Math.pow(zoom, 2) - 0.0006525 * zoom + 1;
}

export interface CanvasProps {
	width: number;
	height: number;

	offsetX: number;
	setOffsetX: (value: number) => void;

	offsetY: number;
	setOffsetY: (value: number) => void;

	zoom: number;
	setZoom: (value: number) => void;
}

export const Canvas: React.FC<CanvasProps> = (props) => {
	const canvasRef = useRef<HTMLCanvasElement | null>(null);

	const idsRef = useRef<Uint32Array | null>(null);

	const offsetXRef = useRef(props.offsetX);
	const offsetYRef = useRef(props.offsetY);
	const zoomRef = useRef(props.zoom);

	const widthRef = useRef(props.width);
	const heightRef = useRef(props.height);

	useEffect(() => {
		if (canvasRef.current === null) {
			return;
		}

		function animate() {
			if (canvasRef.current === null) {
				return;
			}

			const scale = getScale(zoomRef.current);
			const ids = idsRef.current ?? Uint32Array.from([]);
			render(
				canvasRef.current,
				offsetXRef.current,
				offsetYRef.current,
				scale,
				widthRef.current,
				heightRef.current,
				ids
			);

			requestAnimationFrame(animate);
		}

		requestAnimationFrame(animate);
	}, []);

	const handleKeyDown = useCallback((event: React.KeyboardEvent<HTMLCanvasElement>) => {
		const delta = 10 * (1 / getScale(zoomRef.current));
		if (event.key === "ArrowUp") {
			offsetYRef.current += delta;
			props.setOffsetY(offsetYRef.current);
		} else if (event.key === "ArrowDown") {
			offsetYRef.current -= delta;
			props.setOffsetY(offsetYRef.current);
		} else if (event.key === "ArrowRight") {
			offsetXRef.current -= delta;
			props.setOffsetX(offsetXRef.current);
		} else if (event.key === "ArrowLeft") {
			offsetXRef.current += delta;
			props.setOffsetX(offsetXRef.current);
		}
	}, []);
	4;

	const handleScroll = useCallback((event: React.WheelEvent<HTMLCanvasElement>) => {
		zoomRef.current += event.deltaY;
		zoomRef.current = Math.max(zoomRef.current, MIN_ZOOM);
		zoomRef.current = Math.min(zoomRef.current, MAX_ZOOM);
		props.setZoom(zoomRef.current);
	}, []);

	const anchor = useRef<{ x: number; offsetX: number; y: number; offsetY: number } | null>(null);

	const handleMouseDown = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {
		anchor.current = {
			x: event.clientX - props.offsetX,
			offsetX: offsetXRef.current,
			y: event.clientY - props.offsetY,
			offsetY: offsetYRef.current,
		};
	}, []);

	const handleMouseMove = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {
		if (anchor.current === null) {
			return;
		}

		const scale = getScale(zoomRef.current);

		const x = event.clientX - props.offsetX;
		const y = event.clientY - props.offsetY;
		const dx = x - anchor.current.x;
		const dy = y - anchor.current.y;
		offsetXRef.current = anchor.current.offsetX + dx / scale;
		offsetYRef.current = anchor.current.offsetY + dy / scale;
	}, []);

	const handleMouseUp = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {
		anchor.current = null;
		props.setOffsetX(offsetXRef.current);
		props.setOffsetY(offsetYRef.current);
	}, []);

	const handleClick = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {}, []);

	const refreshIds = useDebouncedCallback(
		(area: { minX: number; maxX: number; minY: number; maxY: number; minZ: number }) => {
			idsRef.current = window.env.refresh(area.minX, area.maxX, area.minY, area.maxY, area.minZ);
		},
		100,
		{ leading: true, maxWait: 200 }
	);

	useEffect(() => {
		offsetXRef.current = props.offsetX;
		offsetYRef.current = props.offsetY;
		zoomRef.current = props.zoom;
		widthRef.current = props.width;
		heightRef.current = props.height;

		const scale = getScale(props.zoom);
		const w = props.width / 2;
		const h = props.height / 2;
		const maxX = w / scale - props.offsetX;
		const minX = -w / scale - props.offsetX;
		const maxY = h / scale - props.offsetY;
		const minY = -h / scale - props.offsetY;
		const minZ = getMinZ(scale);
		refreshIds({ minX, maxX, minY, maxY, minZ });
	}, [props.zoom, props.offsetX, props.offsetY, props.width, props.height]);

	return (
		<canvas
			autoFocus
			tabIndex={1}
			width={props.width}
			height={props.height}
			ref={canvasRef}
			onKeyDown={handleKeyDown}
			onWheel={handleScroll}
			onMouseDown={handleMouseDown}
			onMouseMove={handleMouseMove}
			onMouseUp={handleMouseUp}
			onClick={handleClick}
		></canvas>
	);
};
