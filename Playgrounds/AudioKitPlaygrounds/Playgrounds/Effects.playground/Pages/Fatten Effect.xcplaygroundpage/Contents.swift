//: ## Fatten Effect
//: This is a cool stereo fattening effect that Matthew Fecher wanted for the
//: Analog Synth X project, so it was developed here in a playground first.
import AudioKitPlaygrounds
import AudioKit

let file = try AKAudioFile(readFileName: playgroundAudioFiles[0])

let player = try AKAudioPlayer(file: file)
player.looping = true

let fatten = AKOperationEffect(player) { input, parameters in

    let time = parameters[0]
    let mix = parameters[1]

    let fatten = "\(input) dup \(1 - mix) * swap 0 \(time) 1.0 vdelay \(mix) * +"

    return AKStereoOperation(fatten)
}

AudioKit.output = fatten
AudioKit.start()

player.play()

fatten.parameters = [0.1, 0.5]

//: User Interface Set up

class PlaygroundView: AKPlaygroundView {

    override func setup() {
        addTitle("Analog Synth X Fatten")

        addSubview(AKResourcesAudioFileLoaderView(player: player, filenames: playgroundAudioFiles))

        addSubview(AKPropertySlider(property: "Time",
                                    value: fatten.parameters[0],
                                    range: 0.03 ... 0.1,
                                    format:  "%0.3f s"
        ) { sliderValue in
            fatten.parameters[0] = sliderValue
        })

        addSubview(AKPropertySlider(property: "Mix", value: fatten.parameters[1]) { sliderValue in
            fatten.parameters[1] = sliderValue
        })
    }
}

import PlaygroundSupport
PlaygroundPage.current.needsIndefiniteExecution = true
PlaygroundPage.current.liveView = PlaygroundView()
