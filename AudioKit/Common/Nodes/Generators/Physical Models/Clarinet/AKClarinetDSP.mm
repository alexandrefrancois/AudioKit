//
//  AKClarinet.mm
//  AudioKit
//
//  Created by Aurelius Prochazka, revision history on Github.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#import "AKClarinetDSP.hpp"

#include "Clarinet.h"

// "Constructor" function for interop with Swift

extern "C" AKDSPRef createClarinetDSP(int nChannels, double sampleRate) {
    AKClarinetDSP *dsp = new AKClarinetDSP();
    dsp->init(nChannels, sampleRate);
    return dsp;
}

// AKClarinetDSP method implementations

struct AKClarinetDSP::_Internal
{
    float internalTrigger = 0;
    stk::Clarinet *clarinet;
    
    AKLinearParameterRamp frequencyRamp;
    AKLinearParameterRamp amplitudeRamp;
    AKLinearParameterRamp detuningOffsetRamp;
    AKLinearParameterRamp detuningMultiplierRamp;
};

AKClarinetDSP::AKClarinetDSP() : data(new _Internal)
{
    data->frequencyRamp.setTarget(440, true);
    data->frequencyRamp.setDurationInSamples(10000);
    data->amplitudeRamp.setTarget(1, true);
    data->amplitudeRamp.setDurationInSamples(10000);
}

AKClarinetDSP::~AKClarinetDSP() = default;


/** Uses the ParameterAddress as a key */
void AKClarinetDSP::setParameter(AUParameterAddress address, float value, bool immediate)  {
    switch (address) {
        case AKClarinetParameterFrequency:
            data->frequencyRamp.setTarget(value, immediate);
            break;
        case AKClarinetParameterAmplitude:
            data->amplitudeRamp.setTarget(value, immediate);
            break;
        case AKClarinetParameterRampDuration:
            data->frequencyRamp.setRampDuration(value, _sampleRate);
            data->amplitudeRamp.setRampDuration(value, _sampleRate);
            break;
    }
}

/** Uses the ParameterAddress as a key */
float AKClarinetDSP::getParameter(AUParameterAddress address)  {
    switch (address) {
        case AKClarinetParameterFrequency:
            return data->frequencyRamp.getTarget();
        case AKClarinetParameterAmplitude:
            return data->amplitudeRamp.getTarget();
        case AKClarinetParameterRampDuration:
            return data->frequencyRamp.getRampDuration(_sampleRate);
    }
    return 0;
}

void AKClarinetDSP::init(int _channels, double _sampleRate)  {
    AKDSPBase::init(_channels, _sampleRate);
    
    stk::Stk::setSampleRate(_sampleRate);
    data->clarinet = new stk::Clarinet(100);
}

void AKClarinetDSP::trigger() {
    data->internalTrigger = 1;
}

void AKClarinetDSP::triggerFrequencyAmplitude(AUValue freq, AUValue amp)  {
    bool immediate = true;
    data->frequencyRamp.setTarget(freq, immediate);
    data->amplitudeRamp.setTarget(amp, immediate);
    trigger();
}

void AKClarinetDSP::destroy() {
    delete data->clarinet;
}

void AKClarinetDSP::process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) {
    
    for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
        int frameOffset = int(frameIndex + bufferOffset);
        
        // do ramping every 8 samples
        if ((frameOffset & 0x7) == 0) {
            data->frequencyRamp.advanceTo(_now + frameOffset);
            data->amplitudeRamp.advanceTo(_now + frameOffset);
        }
        float frequency = data->frequencyRamp.getValue();
        float amplitude = data->amplitudeRamp.getValue();
        
        for (int channel = 0; channel < _nChannels; ++channel) {
            float *out = (float *)_outBufferListPtr->mBuffers[channel].mData + frameOffset;
            
            if (_playing) {
                if (data->internalTrigger == 1) {
                    data->clarinet->noteOn(frequency, amplitude);
                }
                *out = data->clarinet->tick();
            } else {
                *out = 0.0;
            }
        }
    }
    if (data->internalTrigger == 1) {
        data->internalTrigger = 0;
    }
}
