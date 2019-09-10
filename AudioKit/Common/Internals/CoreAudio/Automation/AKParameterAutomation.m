//
//  AKParameterAutomation.m
//  AudioKit
//
//  Created by Ryan Francesconi on 9/9/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//

//#include <vector>
#import "AKParameterAutomation.h"
#import "AKTimelineTap.h"

@implementation AKParameterAutomation
{
    AKTimelineTap *tap;
    AUAudioUnit *auAudioUnit;
    AVAudioUnit *avAudioUnit;
    Float64 lastRenderTime;

    AVAudioTime *anchorTime;

    AUEventSampleTime endTime;

    AutomationPoint automationPoints[256];
    int numberOfPoints;
}

- (void)initAutomation:(AUAudioUnit *)auAudioUnit avAudioUnit:(AVAudioUnit *)avAudioUnit {
    tap = [[AKTimelineTap alloc]initWithNode:avAudioUnit timelineBlock:[self timelineBlock]];
    tap.preRender = true;

    self->auAudioUnit = auAudioUnit;
    self->avAudioUnit = avAudioUnit;

    //[self clear];
}

- (void)startAutomationAt:(AVAudioTime *)audioTime
                 duration:(AVAudioTime *_Nullable)duration {
    if (AKTimelineIsStarted(tap.timeline)) {
        NSLog(@"startAutomationAt() Timeline is already running");
        return;
    }

    if (@available(macOS 10.13, *)) {
        if ([[avAudioUnit engine] manualRenderingMode] == AVAudioEngineManualRenderingModeOffline) {
            AudioTimeStamp zero = {0};
            tap.timeline->lastRenderTime = zero;
        }
    }

    Float64 sampleRate = tap.timeline->format.mSampleRate;
    lastRenderTime = tap.timeline->lastRenderTime.mSampleTime;

    AUEventSampleTime offsetTime = audioTime.audioTimeStamp.mSampleTime + lastRenderTime;
    anchorTime = [[AVAudioTime alloc]initWithSampleTime:offsetTime atRate:sampleRate];

    endTime = 0;
    if (duration != nil) {
        endTime = duration.audioTimeStamp.mSampleTime;
    }
    //[self validatePoints:audioTime];

    NSLog(@"starting automation at time %lld, lastRenderTime %f, duration %lld", offsetTime, lastRenderTime, endTime);

    //AKTimelineSetTime(tap.timeline, 0);
    AKTimelineSetTimeAtTime(tap.timeline, 0, anchorTime.audioTimeStamp);
    AKTimelineStartAtTime(tap.timeline, anchorTime.audioTimeStamp);
}

- (void)stopAutomation {
    if (!AKTimelineIsStarted(tap.timeline)) {
        NSLog(@"stopAutomation() Timeline isn't running");
        return;
    }
    //AKTimelineSetTime(tap.timeline, 0);
    AKTimelineStop(tap.timeline);

    lastRenderTime = tap.timeline->lastRenderTime.mSampleTime;

    //lastRenderTime = avAudioUnit.lastRenderTime.audioTimeStamp.mSampleTime;

    [self clear];
    NSLog(@"stopping automation at time %f", tap.timeline->lastRenderTime.mSampleTime);
}

- (AKTimelineBlock)timelineBlock {
    // Use untracked pointer and ivars to avoid Obj methods + ARC.
    __unsafe_unretained AKParameterAutomation *welf = self;

    return ^(AKTimeline *timeline,
             AudioTimeStamp *timeStamp,
             UInt32 offset,
             UInt32 inNumberFrames,
             AudioBufferList *ioData) {
               AUEventSampleTime sampleTime = timeStamp->mSampleTime;
               //Float64 lastRenderTime = welf->lastRenderTime;

//               printf("timeStamp %lld inNumberFrames %i\n", sampleTime, inNumberFrames);

               //AUEventSampleTime endTime = welf->endTime;

               //if (sampleTime + inNumberFrames >= welf->anchorTime.audioTimeStamp.mSampleTime) {
               for (int n = 0; n < inNumberFrames; n++) {
                   AUEventSampleTime sampleTimeWithOffset = sampleTime + n;

                   //printf("timeStamp %lld inNumberFrames %i, endTime %lld\n", sampleTimeWithOffset, inNumberFrames, endTime);

//                   if (welf->endTime != 0 && sampleTimeWithOffset == welf->endTime) {
//                       printf("🛑 auto stop at at %lld\n", sampleTimeWithOffset);
//
//                       [welf stopAutomation];
//                       return;
//                   }

                   for (int p = 0; p < welf->numberOfPoints; p++) {
                       AutomationPoint point = welf->automationPoints[p];

                       if (point.triggered) {
                           continue;
                       }

                       if (point.sampleTime == AUEventSampleTimeImmediate) {
                           printf("👍 triggering point %i, address %lld value %f AUEventSampleTimeImmediate at %lld\n", p, point.address, point.value,  sampleTimeWithOffset);
                           welf->auAudioUnit.scheduleParameterBlock(AUEventSampleTimeImmediate,
                                                                    point.rampDuration,
                                                                    point.address,
                                                                    point.value);
                           welf->automationPoints[p].triggered = true;
                           continue;
                       }

                       if (sampleTimeWithOffset == point.sampleTime) {
                           printf("👉 triggering point %i, address %lld value %f at %lld\n", p, point.address, point.value,  point.sampleTime);

                           welf->auAudioUnit.scheduleParameterBlock(AUEventSampleTimeImmediate + n,
                                                                    point.rampDuration,
                                                                    point.address,
                                                                    point.value);
                           welf->automationPoints[p].triggered = true;
                       }
                   }
               }
               //}
//
    };
}

- (void)addPoint:(AUParameterAddress)address
           value:(AUValue)value
      sampleTime:(AUEventSampleTime)sampleTime
      anchorTime:(AUEventSampleTime)anchorTime
    rampDuration:(AUAudioFrameCount)rampDuration {
    struct AutomationPoint point = {};
    point.address = address;
    point.value = value;
    point.sampleTime = sampleTime;
    point.anchorTime = anchorTime;
    point.rampDuration = rampDuration;

    [self addPoint:point];
}

- (void)addPoint:(struct AutomationPoint)point {
    // add to the list of points

    if (numberOfPoints + 1 > 255) {
        NSLog(@"Max number of points was reached.");
        return;
    }

    automationPoints[numberOfPoints] = point;
    NSLog(@"addPoint %i at time %lld, value %f", numberOfPoints, point.sampleTime, point.value);

    numberOfPoints++;
}

- (void)clear {
    // clear all points

//    if (automationPoints != nil) {
//        free(automationPoints);
//    }
    //automationPoints = malloc(256 * sizeof(AutomationPoint));

    memset(self->automationPoints, 0, sizeof(AutomationPoint) * 256);

//    for (int p = 0; p < 256; p++) {
//        AutomationPoint point = automationPoints[p];
//        NSLog(@"? point %i at time %lld, value %f", p, point.sampleTime, point.value);
//    }

    numberOfPoints = 0;
}

- (void)validatePoints:(AVAudioTime *)audioTime {
    Float64 sampleTime = audioTime.audioTimeStamp.mSampleTime;

    for (int i = 0; i <= numberOfPoints; i++) {
        AutomationPoint point = automationPoints[i];

        if (point.sampleTime == AUEventSampleTimeImmediate || point.sampleTime == 0) {
            continue;
        }

        if (point.sampleTime < sampleTime) {
            automationPoints[i].sampleTime = sampleTime;
            printf("→→→ Adjusted late point's time to %f was %lld\n", sampleTime, point.sampleTime);
        }
    }
}

- (void)dispose {
    [self stopAutomation];

    tap = nil;
    auAudioUnit = nil;
    avAudioUnit = nil;
}

//------------------------------------------------------------------------------
#pragma mark - Dealloc
//------------------------------------------------------------------------------

- (void)dealloc
{
    NSLog(@"* { AKParameterAutomation.dealloc }");
}

@end
