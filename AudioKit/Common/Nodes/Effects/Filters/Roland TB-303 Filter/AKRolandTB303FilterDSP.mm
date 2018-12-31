//
//  AKRolandTB303FilterDSP.mm
//  AudioKit
//
//  Created by Aurelius Prochazka, revision history on Github.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#include "AKRolandTB303FilterDSP.hpp"
#import "AKLinearParameterRamp.hpp"

extern "C" AKDSPRef createRolandTB303FilterDSP(int nChannels, double sampleRate) {
    AKRolandTB303FilterDSP *dsp = new AKRolandTB303FilterDSP();
    dsp->init(nChannels, sampleRate);
    return dsp;
}

struct AKRolandTB303FilterDSP::_Internal {
    sp_tbvcf *_tbvcf0;
    sp_tbvcf *_tbvcf1;
    AKLinearParameterRamp cutoffFrequencyRamp;
    AKLinearParameterRamp resonanceRamp;
    AKLinearParameterRamp distortionRamp;
    AKLinearParameterRamp resonanceAsymmetryRamp;
};

AKRolandTB303FilterDSP::AKRolandTB303FilterDSP() : data(new _Internal) {
    data->cutoffFrequencyRamp.setTarget(defaultCutoffFrequency, true);
    data->cutoffFrequencyRamp.setDurationInSamples(defaultRampDurationSamples);
    data->resonanceRamp.setTarget(defaultResonance, true);
    data->resonanceRamp.setDurationInSamples(defaultRampDurationSamples);
    data->distortionRamp.setTarget(defaultDistortion, true);
    data->distortionRamp.setDurationInSamples(defaultRampDurationSamples);
    data->resonanceAsymmetryRamp.setTarget(defaultResonanceAsymmetry, true);
    data->resonanceAsymmetryRamp.setDurationInSamples(defaultRampDurationSamples);
}

// Uses the ParameterAddress as a key
void AKRolandTB303FilterDSP::setParameter(AUParameterAddress address, AUValue value, bool immediate) {
    switch (address) {
        case AKRolandTB303FilterParameterCutoffFrequency:
            data->cutoffFrequencyRamp.setTarget(clamp(value, cutoffFrequencyLowerBound, cutoffFrequencyUpperBound), immediate);
            break;
        case AKRolandTB303FilterParameterResonance:
            data->resonanceRamp.setTarget(clamp(value, resonanceLowerBound, resonanceUpperBound), immediate);
            break;
        case AKRolandTB303FilterParameterDistortion:
            data->distortionRamp.setTarget(clamp(value, distortionLowerBound, distortionUpperBound), immediate);
            break;
        case AKRolandTB303FilterParameterResonanceAsymmetry:
            data->resonanceAsymmetryRamp.setTarget(clamp(value, resonanceAsymmetryLowerBound, resonanceAsymmetryUpperBound), immediate);
            break;
        case AKRolandTB303FilterParameterRampDuration:
            data->cutoffFrequencyRamp.setRampDuration(value, _sampleRate);
            data->resonanceRamp.setRampDuration(value, _sampleRate);
            data->distortionRamp.setRampDuration(value, _sampleRate);
            data->resonanceAsymmetryRamp.setRampDuration(value, _sampleRate);
            break;
    }
}

// Uses the ParameterAddress as a key
float AKRolandTB303FilterDSP::getParameter(uint64_t address) {
    switch (address) {
        case AKRolandTB303FilterParameterCutoffFrequency:
            return data->cutoffFrequencyRamp.getTarget();
        case AKRolandTB303FilterParameterResonance:
            return data->resonanceRamp.getTarget();
        case AKRolandTB303FilterParameterDistortion:
            return data->distortionRamp.getTarget();
        case AKRolandTB303FilterParameterResonanceAsymmetry:
            return data->resonanceAsymmetryRamp.getTarget();
        case AKRolandTB303FilterParameterRampDuration:
            return data->cutoffFrequencyRamp.getRampDuration(_sampleRate);
    }
    return 0;
}

void AKRolandTB303FilterDSP::init(int _channels, double _sampleRate) {
    AKSoundpipeDSPBase::init(_channels, _sampleRate);
    sp_tbvcf_create(&data->_tbvcf0);
    sp_tbvcf_init(_sp, data->_tbvcf0);
    sp_tbvcf_create(&data->_tbvcf1);
    sp_tbvcf_init(_sp, data->_tbvcf1);
    data->_tbvcf0->fco = defaultCutoffFrequency;
    data->_tbvcf1->fco = defaultCutoffFrequency;
    data->_tbvcf0->res = defaultResonance;
    data->_tbvcf1->res = defaultResonance;
    data->_tbvcf0->dist = defaultDistortion;
    data->_tbvcf1->dist = defaultDistortion;
    data->_tbvcf0->asym = defaultResonanceAsymmetry;
    data->_tbvcf1->asym = defaultResonanceAsymmetry;
}

void AKRolandTB303FilterDSP::deinit() {
    sp_tbvcf_destroy(&data->_tbvcf0);
    sp_tbvcf_destroy(&data->_tbvcf1);
}

void AKRolandTB303FilterDSP::process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) {

    for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
        int frameOffset = int(frameIndex + bufferOffset);

        // do ramping every 8 samples
        if ((frameOffset & 0x7) == 0) {
            data->cutoffFrequencyRamp.advanceTo(_now + frameOffset);
            data->resonanceRamp.advanceTo(_now + frameOffset);
            data->distortionRamp.advanceTo(_now + frameOffset);
            data->resonanceAsymmetryRamp.advanceTo(_now + frameOffset);
        }

        data->_tbvcf0->fco = data->cutoffFrequencyRamp.getValue();
        data->_tbvcf1->fco = data->cutoffFrequencyRamp.getValue();
        data->_tbvcf0->res = data->resonanceRamp.getValue();
        data->_tbvcf1->res = data->resonanceRamp.getValue();
        data->_tbvcf0->dist = data->distortionRamp.getValue();
        data->_tbvcf1->dist = data->distortionRamp.getValue();
        data->_tbvcf0->asym = data->resonanceAsymmetryRamp.getValue();
        data->_tbvcf1->asym = data->resonanceAsymmetryRamp.getValue();

        float *tmpin[2];
        float *tmpout[2];
        for (int channel = 0; channel < _nChannels; ++channel) {
            float *in  = (float *)_inBufferListPtr->mBuffers[channel].mData  + frameOffset;
            float *out = (float *)_outBufferListPtr->mBuffers[channel].mData + frameOffset;
            if (channel < 2) {
                tmpin[channel] = in;
                tmpout[channel] = out;
            }
            if (!_playing) {
                *out = *in;
                continue;
            }

            if (channel == 0) {
                sp_tbvcf_compute(_sp, data->_tbvcf0, in, out);
            } else {
                sp_tbvcf_compute(_sp, data->_tbvcf1, in, out);
            }
        }
    }
}
