--!strict

export type PlaySettings = {
	fadeTime: number?,
	weight: number?,
	speed: number?
}

export type PlayEvents = {
	[string]: (...string) -> (),
}


local Module = {}

function Module.getAnimator(model: Model)
	local modelAnimator = model:FindFirstChildWhichIsA('Animator', true) or model:FindFirstChildWhichIsA('Humanoid', true)
	assert(modelAnimator, `{if typeof(model) == 'Instance' then model:GetFullName() else tostring(model)} has no Animator or Humanoid`)
	return modelAnimator
end

Module.cache = {}

function Module.getAnimationTrack(model: Model, animation: Animation): (AnimationTrack, { speed: number }, { [string]: RBXScriptConnection })
	local modelAnimator = Module.getAnimator(model)

	local cache = Module.cache[model]
	if not cache then
		local tracks = modelAnimator:GetPlayingAnimationTracks() -- Deprecated but still works so we're keeping it (IT'S USEFUL WHY?!?!?)
		for _, track in tracks do
			if track.Name == animation.Name then
				return track, { speed = 1 }, {}
			end
		end
	end

	if not cache then
		cache = {}
		Module.cache[model] = cache

		model.Destroying:Once(function()
			for animation, cached in cache do
				cached.track:Destroy()
				for _, connection in cached.events do
					connection:Disconnect()
				end
			end
			Module.cache[model] = nil
		end)
	end

	local cachedTrack = cache[animation]
	if cachedTrack then
		return cachedTrack.track, cachedTrack.settings, cachedTrack.events
	end

	local track = (modelAnimator :: Animator):LoadAnimation(animation)
	local settings = {
		speed = animation:GetAttribute 'Speed'  or 1;
	}
	local events = {}

	cache[animation] = {
		track = track,
		settings = settings,
		events = events,
	}

	return track, settings, events
end

function Module.playAnimation(model: Model, animation: Animation, playSettings: PlaySettings?)
	local animationTrack, settings, _ = Module.getAnimationTrack(model, animation)
	if not animationTrack.IsPlaying then
		local fadeTime = playSettings and playSettings.fadeTime
		local weight = playSettings and playSettings.weight
		animationTrack:Play(fadeTime, weight)
	end

	local speed = if playSettings then playSettings.speed else settings.speed
	animationTrack:AdjustSpeed(speed)

	return {
		track = animationTrack,
	}
end

export type PlayAnimation = typeof(Module.playAnimation(...))

function Module.connectAnimation(model: Model, animation: Animation, playEvents: PlayEvents)
	local animationTrack, _, events = Module.getAnimationTrack(model, animation)
	for eventName, callback in playEvents do
		local old = events[eventName]
		if old and old.Connected then
			old:Disconnect()
		end

		events[eventName] = animationTrack:GetMarkerReachedSignal(eventName):Connect(callback)
	end
end

function Module.stopAnimation(model: Model, animation: Animation, fadeTime: number?)
	local animationTrack = Module.getAnimationTrack(model, animation)
	animationTrack:Stop(fadeTime or 0.3)
end

function Module.pauseAnimation(model: Model, animation: Animation)
	local animationTrack = Module.getAnimationTrack(model, animation)
	animationTrack:AdjustSpeed(0)
end

function Module.isPlaying(model: Model, animation: Animation)
	local animationTrack = Module.getAnimationTrack(model, animation)
	return animationTrack.IsPlaying
end

function Module.getExclusivePlay(animations: { Animation }, pauseInstead: true?)
	return function(model: Model, animation: Animation?, playSettings: PlaySettings?, playEvents: PlayEvents?): PlayAnimation?
		if animation and not table.find(animations, animation) then
			error(`{animation:GetFullName()} is not in the provided animations list: {animations}`)
		end

		if not pauseInstead then
			for _, other in animations do
				if other ~= animation then
					Module.stopAnimation(model, other)
				end
			end
		else
			for _, other in animations do
				if other ~= animation then
					Module.pauseAnimation(model, other)
				end
			end
		end

		if animation then
			if playEvents then
				Module.connectAnimation(model, animation, playEvents)
			end

			return Module.playAnimation(model, animation, playSettings)
		end

		return nil
	end
end

export type ExclusivePlay = typeof(Module.getExclusivePlay(...))

return Module