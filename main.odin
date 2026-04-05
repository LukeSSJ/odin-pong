package main

import "core:fmt"
import "core:math/rand"
import sdl "vendor:sdl3"

Key :: struct {
	up: bool,
	down: bool,
}

Vector2 :: struct {
	x: f32,
	y: f32,
}

Ball :: struct {
	x: f32,
	y: f32,
	x_speed: f32,
	y_speed: f32,
	delay: int,
	last_hit: int,
}

window: ^sdl.Window
ball := Ball{}
key := Key{}
trail := [8]Vector2{}
scores := [2]int{0,0}

audio_loaded := false
spec := sdl.AudioSpec{}
audio_buf: [^]u8
audio_len: u32
device: sdl.AudioDeviceID = 0
stream: ^sdl.AudioStream

main :: proc() {
	if !sdl.Init({.VIDEO, .AUDIO}) {
		fmt.println("Failed to init SDL:", sdl.GetError())
		return
	}
	defer sdl.Quit()

	window = sdl.CreateWindow("Pong", 640, 480, {})
	if window == nil {
		fmt.println("Failed to create window:", sdl.GetError())
		return
	}
	defer sdl.DestroyWindow(window)

	renderer := sdl.CreateRenderer(window, nil)
	if renderer == nil {
		fmt.println("Failed to create renderer:", sdl.GetError())
		return
	}
	defer sdl.DestroyRenderer(renderer)

	sdl.SetRenderDrawBlendMode(renderer, sdl.BLENDMODE_BLEND)

	load_audio()
	defer cleanup_audio()

	paddles := []f32{240, 240}

	event: sdl.Event

	reset_ball()

	main_loop: for {
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break main_loop
			case .KEY_DOWN:
				key_event(event.key.scancode, true)
			case .KEY_UP:
				key_event(event.key.scancode, false)
			}
		}

		if key.up {
			paddles[0] -= 8
		}
		if key.down {
			paddles[0] += 8
		}

		if ball.x_speed > 0 {
			if ball.y < paddles[1] {
				paddles[1] -= 4
			}
			if ball.y > paddles[1] {
				paddles[1] += 4
			}
		}

		for &paddle in paddles {
			if paddle < 50 {
				paddle = 50
			}
			if paddle > 480 - 50 {
				paddle = 480 - 50
			}
		}

		if ball.delay > 0 {
			ball.delay -= 1
			if ball.delay == 0 {
				ball.x_speed = -4
				ball.y_speed = rand.float32_range(0.5, 2.0)
				// ball.y_speed = 0
				if rand.int_range(0, 2) == 1 {
					ball.y_speed *= -1
				}
			}
		}

		for i := len(trail) - 1; i > 0; i -= 1 {
			trail[i].x = trail[i - 1].x
			trail[i].y = trail[i - 1].y
		}
		trail[0].x = ball.x
		trail[0].y = ball.y

		ball.x += ball.x_speed
		ball.y += ball.y_speed

		if ball.x < 20 && abs(ball.y - paddles[0]) <= 50 && ball.last_hit != 0 {
			ball_bounce(0)
		}
		if ball.x > 640 - 20 && abs(ball.y - paddles[1]) <= 50 && ball.last_hit != 1  {
			ball_bounce(1)
		}

		if ball.x < -20 {
			ball_missed(1)
			reset_ball()
		}
		if ball.x > 640 + 20 {
			ball_missed(0)
			reset_ball()
		}
		if ball.y < 10 || ball.y > 480 - 10 {
			ball.y_speed = - ball.y_speed
		}

		sdl.SetRenderDrawColor(renderer, 0, 0, 0, 255);
		sdl.RenderClear(renderer);

		sdl.SetRenderDrawColor(renderer, 255, 255, 255, 100)
		for position, i in trail {
			offset := 10 - f32(i)
			rect := sdl.FRect{x = position.x - offset, y = position.y - offset, w = offset * 2, h = offset * 2}
			sdl.RenderFillRect(renderer, &rect)
		}

		rect := sdl.FRect{x = ball.x - 10, y = ball.y - 10, w = 20, h = 20}
		sdl.SetRenderDrawColor(renderer, 255, 255, 255, 255)
		sdl.RenderFillRect(renderer, &rect)

		for i in 0..<2 {
			rect := sdl.FRect{x = i == 0 ? 10 : 640 - 20, y = paddles[i] - 50, w = 10, h = 100}
			sdl.RenderFillRect(renderer, &rect)
		}

		sdl.RenderPresent(renderer);

		sdl.Delay(16);
	}
}

reset_ball :: proc() {
	ball.x = 320
	ball.y = 240
	ball.x_speed = 0
	ball.y_speed = 0
	ball.delay = 30
	ball.last_hit = -1

	for &position in trail {
		position.x = ball.x
		position.y = ball.y
	}
}

ball_bounce :: proc(side: int) {
	ball.x_speed = - ball.x_speed
	ball.x_speed *= 1.1
	ball.y_speed *= 1.1
	ball.last_hit = side

	if audio_loaded {
		sdl.ClearAudioStream(stream)
		sdl.PutAudioStreamData(stream, audio_buf, i32(audio_len))
	}
}

ball_missed :: proc(side: int) {
	scores[side] += 1

	sdl.SetWindowTitle(window, fmt.ctprintf("Pong %d - %d", scores[0], scores[1]))
}

key_event :: proc(scancode: sdl.Scancode, pressed: bool) {
	#partial switch scancode {
	case .UP:
		key.up = pressed
	case .DOWN:
		key.down = pressed
	}
}

load_audio :: proc() {
	if !sdl.LoadWAV("pong.wav", &spec, &audio_buf, &audio_len) {
		fmt.println("Failed to load audio:", sdl.GetError())
		return
	}

	device = sdl.OpenAudioDevice(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec)
	if device == 0 {
		fmt.println("Failed to open audio device:", sdl.GetError())
		return
	}

	stream = sdl.CreateAudioStream(&spec, &spec)
	if stream == nil {
		fmt.println("Failed to create audio stream:", sdl.GetError())
		return
	}

	if !sdl.BindAudioStream(device, stream) {
		fmt.println("Failed to bind audio stream:", sdl.GetError())
		return
	}

	audio_loaded = true
}

cleanup_audio :: proc() {
	if audio_buf != nil {
		sdl.free(audio_buf)
	}
	if device != 0 {
		sdl.CloseAudioDevice(device)
	}
	if stream != nil {
		sdl.DestroyAudioStream(stream)
	}
}
