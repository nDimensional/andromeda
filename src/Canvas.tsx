import React, { useRef, useEffect, useCallback } from "react";
import { useDebouncedCallback } from "use-debounce";

import { getScale, MIN_ZOOM, MAX_ZOOM, getMinZ, render } from "./render.js";
import "./api.js";

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

const devicePixelRatio = window.devicePixelRatio;
console.log("devicePixelRatio", devicePixelRatio);

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
				devicePixelRatio * widthRef.current,
				devicePixelRatio * heightRef.current,
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

	const handleWheel = useCallback((event: React.WheelEvent<HTMLCanvasElement>) => {
		if (canvasRef.current === null) {
			return;
		}

		let zoom = zoomRef.current + event.deltaY;
		zoom = Math.max(zoom, MIN_ZOOM);
		zoom = Math.min(zoom, MAX_ZOOM);
		if (zoom !== zoomRef.current) {
			const oldScale = getScale(zoomRef.current);
			const newScale = getScale(zoom);
			props.setZoom(zoom);
			zoomRef.current = zoom;

			const clientX = event.clientX - canvasRef.current.offsetLeft;
			const clientY = event.clientY - canvasRef.current.offsetTop;
			const px = clientX - widthRef.current / 2;
			const py = heightRef.current / 2 - clientY;
			const oldX = px / oldScale;
			const oldY = py / oldScale;
			const newX = px / newScale;
			const newY = py / newScale;
			offsetXRef.current += devicePixelRatio * (newX - oldX);
			props.setOffsetX(offsetXRef.current);
			offsetYRef.current += devicePixelRatio * (newY - oldY);
			props.setOffsetY(offsetYRef.current);
		}
	}, []);

	const isDraggingRef = useRef(false);

	const handleMouseEnter = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {}, []);
	const handleMouseLeave = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {
		if (isDraggingRef.current) {
			isDraggingRef.current = false;
			props.setOffsetX(offsetXRef.current);
			props.setOffsetY(offsetYRef.current);
		}
	}, []);

	const handleMouseDown = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {
		isDraggingRef.current = true;
	}, []);

	const handleMouseMove = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {
		if (isDraggingRef.current) {
			const scale = getScale(zoomRef.current);
			offsetXRef.current += (devicePixelRatio * event.movementX) / scale;
			offsetYRef.current -= (devicePixelRatio * event.movementY) / scale;
		}
	}, []);

	const handleMouseUp = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {
		if (isDraggingRef.current) {
			isDraggingRef.current = false;
			props.setOffsetX(offsetXRef.current);
			props.setOffsetY(offsetYRef.current);
		}
	}, []);

	const refreshIds = useDebouncedCallback(
		(minX: number, maxX: number, minY: number, maxY: number, minZ: number) => {
			idsRef.current = window.env.refresh(minX, maxX, minY, maxY, minZ);
		},
		100,
		{ leading: true, trailing: true, maxWait: 200 }
	);

	useEffect(() => {
		offsetXRef.current = props.offsetX;
		offsetYRef.current = props.offsetY;
		zoomRef.current = props.zoom;
		widthRef.current = props.width;
		heightRef.current = props.height;

		const scale = getScale(props.zoom);
		const w = (devicePixelRatio * props.width) / 2;
		const h = (devicePixelRatio * props.height) / 2;
		const maxX = w / scale - props.offsetX;
		const minX = -w / scale - props.offsetX;
		const maxY = h / scale - props.offsetY;
		const minY = -h / scale - props.offsetY;
		const minZ = getMinZ(scale);
		refreshIds(minX, maxX, minY, maxY, minZ);
	}, [props.zoom, props.offsetX, props.offsetY, props.width, props.height]);

	return (
		<canvas
			style={{ width: "100%", height: "100%" }}
			tabIndex={1}
			width={devicePixelRatio * props.width}
			height={devicePixelRatio * props.height}
			ref={canvasRef}
			onKeyDown={handleKeyDown}
			onWheel={handleWheel}
			onMouseEnter={handleMouseEnter}
			onMouseLeave={handleMouseLeave}
			onMouseDown={handleMouseDown}
			onMouseMove={handleMouseMove}
			onMouseUp={handleMouseUp}
		></canvas>
	);
};
