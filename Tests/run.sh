#!/bin/bash
# Compiles the pure Claude sources with the tests and runs them.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
python3 -I "$DIR/singleton-init-lint.py" "$DIR/.." || { echo "SINGLETON INIT LINT FAILED"; exit 1; }
python3 -I "$DIR/side-demo-lint.py" "$DIR/.." || { echo "SIDE DEMO LINT FAILED"; exit 1; }
python3 -I "$DIR/onboarding-strings-lint.py" "$DIR/.." || { echo "ONBOARDING STRINGS LINT FAILED"; exit 1; }
python3 -I "$DIR/team-strings-lint.py" "$DIR/.." || { echo "TEAM STRINGS LINT FAILED"; exit 1; }
python3 -I "$DIR/applescript-lint.py" "$DIR/.." || { echo "APPLESCRIPT LINT FAILED"; exit 1; }
# The skills sandboxes, probed for real before the tests (sandbox-exec can't run inside ARIS_TEST_SANDBOX).
bash "$DIR/skills-sandbox-probe/probe.sh" || { echo "SKILLS SANDBOX PROBE FAILED"; exit 1; }
SRC="$DIR/../Aris/private/Claude"
OUT="${OUT:-$(mktemp -d)/claude-tests}"
swiftc -o "$OUT" "$DIR/main.swift" "$SRC/ClaudeModels.swift" "$SRC/ClaudeStore.swift" \
  "$SRC/ClaudeSounds.swift" "$SRC/HTTPRequestParser.swift" "$SRC/ClaudeHookToken.swift" \
  "$SRC/GrowDownFrame.swift" "$SRC/ClaudeAccent.swift" "$SRC/ClaudeCharacter.swift" "$SRC/ClaudeEarLayout.swift" \
  "$SRC/ClaudeQuestionFlow.swift" \
  "$SRC/TerminalRef.swift" \
  "$SRC/ClaudeUsage.swift" "$SRC/ClaudeRingMode.swift" "$SRC/ClaudeSpend.swift" "$SRC/ClaudeBudget.swift" "$SRC/ClaudeEarDots.swift" "$DIR/claude-usage-tests.swift" \
  "$SRC/ClaudeEarCenter.swift" \
  "$SRC/ClaudeNoticeLabel.swift" "$SRC/../Aris/Home/ArisNotchHeaderLayout.swift" "$SRC/../Aris/Home/ArisTagText.swift" "$SRC/../Aris/Home/ArisShelfTileLayout.swift" "$SRC/../Aris/Team/ArisPillLayout.swift" \
  "$SRC/ApprovalAutoClose.swift" \
  "$SRC/../Aris/ArisIntent.swift" "$SRC/../Aris/ArisNumbers.swift" "$SRC/../Aris/ArisVocabulary.swift" "$SRC/../Aris/ArisDictationCleaner.swift" "$SRC/../Aris/ArisDictationKey.swift" "$SRC/../Aris/ArisDeixis.swift" "$SRC/../Aris/ArisBrief.swift" "$SRC/../Aris/ArisTodos.swift" "$SRC/../Aris/ArisBoardContent.swift" "$SRC/../Aris/ArisClipboard.swift" "$SRC/../Aris/ArisTimerState.swift" "$SRC/../Aris/ArisUsage.swift" "$SRC/../Aris/ArisAgenda.swift" "$SRC/../Aris/Side/ArisSlidingTabsGeometry.swift" "$SRC/../Aris/Side/ArisActivityTimeline.swift" "$SRC/../Aris/ArisDictationPolish.swift" "$SRC/../Aris/ArisSession.swift" "$SRC/../Aris/ArisTurnClosing.swift" "$SRC/../Aris/ArisSpeech.swift" "$SRC/../Aris/ArisLanguages.swift" "$SRC/../Aris/ArisScribe.swift" \
  "$SRC/../Aris/ArisNotch.swift" "$SRC/../Aris/ArisTalkKey.swift" "$SRC/../Aris/ArisElevenLabs.swift" \
  "$SRC/../Aris/ArisKeyFile.swift" "$SRC/../Aris/ArisRouter.swift" "$SRC/../Aris/ArisTuningLog.swift" "$SRC/../Aris/ArisTranscript.swift" "$SRC/../Aris/ArisContext.swift" "$SRC/../Aris/ArisUserName.swift" \
  "$SRC/../Aris/ArisBrain.swift" "$SRC/../Aris/ArisWakeWord.swift" "$SRC/../Aris/ArisVoicePrint.swift" "$SRC/../Aris/ArisVoiceGate.swift" "$SRC/../Aris/ArisFollowUp.swift" "$SRC/../Aris/ArisConversation.swift" "$SRC/../Aris/ArisBargeIn.swift" "$SRC/../Aris/ArisEchoTrim.swift" "$SRC/../Aris/ArisCardKeys.swift" "$SRC/../Aris/ArisOtherAudio.swift" "$SRC/../Aris/Team/ArisHandOutPlan.swift" "$DIR/../ArisAgent/ArisHandsFree.swift" "$DIR/conversation-tests.swift" "$SRC/../Aris/ArisEndpoint.swift" "$SRC/../Aris/ArisSentenceSplitter.swift" "$SRC/../Aris/ArisConfirmReply.swift" "$SRC/../Aris/ArisCountdown.swift" "$DIR/countdown-tests.swift" "$DIR/countdown-parity-tests.swift" "$DIR/../ArisAgent/ArisMessageGate.swift" "$DIR/../ArisTools/ArisMessageRequest.swift" "$SRC/../Aris/ArisHandoff.swift" "$SRC/../Aris/ArisHistory.swift" "$SRC/../Aris/ArisRetryBackoff.swift" "$SRC/../Aris/ArisNotchSnapshot.swift" "$SRC/../Aris/ArisJobLoss.swift" "$SRC/../Aris/ArisAgentCopy.swift" "$SRC/../Aris/ArisAgentLink.swift" "$SRC/../Aris/ArisSpeechModel.swift" "$DIR/../Shared/ArisAgentKickstart.swift" "$DIR/../Shared/ArisXPCTrust.swift" "$SRC/../Aris/ArisMicRestart.swift" "$SRC/../Aris/ArisJSONFile.swift" "$SRC/../Aris/ArisLogRotation.swift" "$DIR/../ArisAgent/ArisProcessEnd.swift" "$DIR/../ArisAgent/ArisAuditThrottle.swift" "$DIR/../ArisAgent/ArisAuditWriter.swift" "$DIR/../ArisAgent/ArisAskAdmission.swift" "$SRC/../Aris/ArisMicChoice.swift" "$SRC/../Aris/ArisDucking.swift" "$SRC/../Aris/ArisAudioQuiet.swift" "$SRC/../Aris/ArisTurnStats.swift" "$SRC/../Aris/Home/ArisAnswerLayout.swift" "$SRC/../Aris/Home/ArisTurnLayout.swift" "$SRC/KeyboardTextInput.swift" "$SRC/../Aris/Home/ArisAnswerMarkdown.swift" "$SRC/../Aris/Home/ArisAnswerAttributed.swift" "$SRC/../Aris/ArisReplyPacer.swift" "$SRC/../Aris/Design/ArisRimSweep.swift" "$SRC/../Aris/See/ArisImageBudget.swift" "$SRC/../Aris/See/ArisImageCodec.swift" "$SRC/../Aris/See/ArisCaptureRules.swift" "$SRC/../Aris/ArisImageCheck.swift" "$SRC/../Aris/ArisTurnImage.swift" "$SRC/../Aris/ArisSpeakable.swift" "$DIR/../ArisAgent/ArisImageRouting.swift" "$DIR/../ArisTools/ArisSealedTools.swift" "$DIR/../ArisAgent/ArisTurnLog.swift" \
  "$DIR/../ArisAgent/ArisUsagePricing.swift" "$DIR/../ArisAgent/ArisUsageCost.swift" "$DIR/../ArisAgent/ArisCodexUsageLedger.swift" "$DIR/../ArisAgent/ArisLineStream.swift" "$DIR/../ArisAgent/ArisUsageFetch.swift" "$DIR/../ArisAgent/ArisAgentStream.swift" "$DIR/../ArisAgent/ArisShortcuts.swift" "$DIR/../ArisAgent/ArisArrange.swift" "$DIR/../ArisAgent/ArisInsert.swift" "$DIR/../ArisAgent/ArisLook.swift" \
  "$DIR/../ArisAgent/ArisCommandPolicy.swift" "$DIR/../ArisAgent/ArisAgentPrompt.swift" "$DIR/../ArisAgent/ArisBrainDriver.swift" \
  "$DIR/../ArisAgent/ArisCodexDriver.swift" "$DIR/../ArisAgent/ArisCodexDriver+ComputerUse.swift" "$DIR/../ArisAgent/ArisAntigravityDriver.swift" "$DIR/../ArisAgent/ArisAgentStatus.swift" "$DIR/../ArisAgent/ArisRiskPolicy.swift" "$DIR/../ArisAgent/ArisRiskPolicy+Dictation.swift" "$DIR/../ArisAgent/ArisRiskPolicy+Provenance.swift" "$DIR/../ArisAgent/ArisTaskResult.swift" "$DIR/../ArisAgent/ArisBrainHealth.swift" "$DIR/../ArisAgent/ArisBrainFailure.swift" \
  "$DIR/../ArisAgent/ArisEscalation.swift" "$DIR/../ArisAgent/ArisAppIdentity.swift" "$DIR/../ArisAgent/ArisJSProgram.swift" "$DIR/../ArisAgent/ArisChunkJudge.swift" "$DIR/../ArisAgent/ArisStandingPermissions.swift" "$DIR/../ArisAgent/ArisApprovalQueue.swift" "$DIR/../ArisAgent/ArisJudge.swift" "$DIR/../ArisAgent/ArisToolScope.swift" "$DIR/../ArisAgent/ArisRiskPolicy+Escalation.swift" "$SRC/../Aris/ArisAgentReply.swift" "$SRC/../Aris/Team/ArisJob.swift" "$SRC/../Aris/Team/ArisDispatch.swift" "$SRC/../Aris/Team/ArisWorkerQueue.swift" "$SRC/../Aris/Team/ArisJobRouting.swift" "$SRC/../Aris/Team/ArisStatusLine.swift" "$SRC/../Aris/Team/ArisBubbleText.swift" "$SRC/../Aris/Team/ArisCharacterDirector.swift" "$SRC/../Aris/Team/ArisCharacter.swift" "$SRC/../Aris/Team/ArisSprite.swift" "$SRC/../Aris/Team/ArisPerchGeometry.swift" "$SRC/../Aris/Team/ArisWindowLocator.swift" "$SRC/../Aris/Team/ArisFollowRules.swift" "$SRC/../Aris/Team/ArisTravelRoute.swift" "$SRC/../Aris/Team/ArisTravelStyle.swift" "$SRC/../Aris/Team/ArisHopPath.swift" "$SRC/../Aris/Team/ArisGlidePath.swift" "$SRC/../Aris/Team/ArisGlideLanding.swift" "$SRC/../Aris/Team/ArisTravelTimeline.swift" "$SRC/../Aris/Team/ArisStrainClip.swift" "$SRC/../Aris/Team/ArisFramePacing.swift" \
  "$SRC/../Aris/Team/ArisTeammate.swift" "$SRC/../Aris/Team/ArisTeammateScope.swift" "$SRC/../Aris/Team/ArisTeamCopy.swift" "$SRC/../Aris/Team/ArisTeamTemplates.swift" "$SRC/../Aris/Team/ArisHelpers.swift" "$SRC/../Aris/Team/ArisTeamRouting+Direct.swift" "$SRC/../Aris/Team/ArisTeamMadeAnswer.swift" "$SRC/../Aris/Team/ArisTeamRemoval.swift" "$SRC/../Aris/Team/ArisNoteRow.swift" "$DIR/team-v2-tests.swift" "$DIR/team-v2-review-tests.swift" "$DIR/team-qa-tests.swift" "$DIR/bughunt-1108-tests.swift" "$DIR/decisions-1108-tests.swift" "$DIR/decisions-followup-tests.swift" "$DIR/../ArisAgent/ArisNotes.swift" "$DIR/../ArisAgent/ArisNotesStore.swift" "$DIR/../ArisAgent/ArisTeamExtrasRoute.swift" "$DIR/../ArisAgent/ArisTeammateJobs.swift" "$DIR/../ArisAgent/ArisTeammateScope+Gate.swift" "$SRC/../Aris/Team/ArisFace.swift" "$DIR/face-tests.swift" "$SRC/../Aris/Team/ArisTeamEditing.swift" "$SRC/../Aris/Team/ArisClaudeLaunch.swift" "$SRC/../Aris/Team/ArisTeammateCompletion.swift" \
  "$DIR/../ArisAgent/ArisTeammateStore.swift" "$DIR/../ArisAgent/ArisTeammateEdit.swift" "$DIR/../ArisAgent/ArisTeammateGate.swift" "$DIR/../ArisAgent/ArisTeammateLauncher.swift" "$DIR/../ArisAgent/ArisPeer.swift" \
  "$DIR/../ArisTools/ArisWeather.swift" "$DIR/../ArisAgent/ArisMemoryText.swift" "$DIR/../ArisAgent/ArisMemoryRecall.swift" "$DIR/../ArisAgent/ArisMemoryStore.swift" "$DIR/../ArisAgent/ArisMemoryLearning.swift" "$DIR/../ArisAgent/ArisMemoryIntent.swift" "$DIR/../ArisAgent/ArisMemoryCurator.swift" "$DIR/memory-tests.swift" "$DIR/../ArisTools/ArisActions.swift" "$DIR/../ArisTools/ArisWindowGrid.swift" "$DIR/../ArisTools/ArisCanvas.swift" "$DIR/../ArisTools/ArisFiles.swift" "$DIR/../ArisTools/ArisActivity.swift" "$DIR/../ArisTools/ArisProtectedPlaces.swift" "$DIR/../ArisTools/ArisUndoArguments.swift" "$DIR/../ArisAgent/ArisActivityBridge.swift" "$DIR/../ArisAgent/ArisPendingUndos.swift" \
  "$DIR/../ArisAgent/ArisSchedule.swift" "$DIR/../ArisAgent/ArisScheduleStore.swift" "$DIR/../ArisTools/ArisScheduleTool.swift" "$SRC/../Aris/ArisInboxItem.swift" \
  "$SRC/../Aris/Gesture/ArisGestureConstants.swift" "$SRC/../Aris/Gesture/ArisGestureDetector.swift" "$SRC/../Aris/Gesture/ArisSpeechActivity.swift" "$SRC/../Aris/Gesture/ArisGestureMarkers.swift" "$SRC/../Aris/Gesture/ArisGestureGeometry.swift" "$SRC/../Aris/Gesture/ArisGestureSession.swift" "$SRC/../Aris/Gesture/ArisInkRenderer.swift" "$SRC/../Aris/Gesture/ArisInkSmoothing.swift" "$SRC/../Aris/Gesture/ArisPointerSampler.swift" "$SRC/../Aris/Gesture/ArisGestureMotion.swift" "$SRC/../Aris/Gesture/ArisGestureChrome.swift" "$SRC/../Aris/Gesture/ArisInkOverlay.swift" "$SRC/../Aris/Gesture/ArisGestureHint.swift" "$SRC/../Aris/Gesture/ArisCircleHint.swift" "$SRC/../Aris/Gesture/ArisGestureKey.swift" "$SRC/../Aris/Gesture/ArisGestureCapturing.swift" "$SRC/../Aris/Gesture/ArisGestureController.swift" "$SRC/../Aris/Gesture/ArisGestureShot.swift" "$SRC/../Aris/Gesture/ArisGestureTurn.swift" "$SRC/../Aris/Gesture/ArisWindowAtPoint.swift" "$SRC/../Aris/Gesture/ArisGestureCapture.swift" "$SRC/../Aris/Gesture/ArisWindowPick.swift" "$SRC/../Aris/Gesture/ArisWindowPickShot.swift" "$DIR/window-pick-tests.swift" "$SRC/../Aris/See/ArisScreenPermissionNotice.swift" "$SRC/../Aris/See/ArisCaptureTiming.swift" "$SRC/../Aris/See/ArisTaskRace.swift" "$SRC/../Aris/See/ArisNotchPresence.swift" "$SRC/../Aris/See/ArisTurnCapture.swift" \
  "$DIR/settings-data-tests.swift" "$SRC/../Aris/ArisDataSafety.swift" "$SRC/../Aris/Onboarding/ArisOnboardingFlow.swift" "$SRC/../Aris/Onboarding/ArisOnboardingStage.swift" "$SRC/../Aris/Onboarding/ArisOnboardingClocks.swift" "$SRC/../Aris/Onboarding/ArisOnboardingModel.swift" "$SRC/../Aris/Onboarding/ArisOnboardingMotion.swift" "$SRC/../Aris/Onboarding/ArisOnboardingScore.swift" "$SRC/../Aris/Onboarding/ArisOnboardingNotchForm.swift" "$SRC/../Aris/Onboarding/ArisOnboardingTimeline.swift" "$SRC/../Aris/Onboarding/ArisOnboardingAudioPlan.swift" "$SRC/../Aris/Onboarding/ArisOnboardingLanguage.swift" "$SRC/../Aris/Onboarding/ArisOnboardingCopy.swift" "$DIR/onboarding-tests.swift" "$DIR/qa-voice-tests.swift" "$SRC/../Aris/Onboarding/ArisOnboardingPractice.swift" "$SRC/../Aris/ArisAppData.swift" "$DIR/../ArisAgent/ArisDataRoute.swift" "$DIR/../ArisAgent/ArisNoFollow.swift" "$DIR/../ArisAgent/ArisUninstallCleanup.swift" "$DIR/../ArisAgent/ArisDiagnosticsFilter.swift" \
  "$DIR/settings-catalog-tests.swift" "$SRC/../Aris/ArisMemorySettings.swift" "$DIR/../Aris/components/Settings/ArisSettingsCatalog.swift" "$DIR/../Aris/components/Settings/ArisSettingsWords.swift" "$DIR/../Aris/components/Settings/ArisSettingsModel.swift" "$DIR/../Aris/components/Settings/ArisSettingsSnapshot.swift" "$DIR/../Aris/components/Settings/ArisSettingsBuilder.swift" "$DIR/../Aris/components/Settings/ArisMoreSettings.swift" "$DIR/../Aris/components/Settings/ArisNotchPreviewPlan.swift" \
  "$DIR/widget-tests.swift" "$SRC/../Aris/ArisWidget.swift" "$DIR/../ArisAgent/ArisWidgetPick.swift" \
  "$DIR/stock-map-tests.swift" "$SRC/../Aris/ArisWidgetStockMap.swift" "$DIR/../ArisTools/ArisStock.swift" "$DIR/../ArisTools/ArisMapsCard.swift" \
  "$DIR/team-dispatch-tests.swift" "$DIR/side-demo-tests.swift" "$SRC/../Aris/Side/ArisSideDemoSamples.swift" "$DIR/ad-demo-tests.swift" "$SRC/../Aris/Demo/ArisAdDemoScript.swift" "$SRC/../Aris/Demo/ArisCaptureSharing.swift" "$SRC/../Aris/Team/ArisOverlayPanels.swift" "$DIR/calendar-tests.swift" "$SRC/../Calendar/ArisCalendarEvent.swift" "$SRC/../Calendar/ArisMeetingLink.swift" "$SRC/../Calendar/ArisCalendarSelection.swift" "$SRC/../Calendar/ArisCalendarStore.swift" "$SRC/../Calendar/ArisEventKitSource.swift" \
  "$DIR/platform-tests.swift" "$SRC/../Platform/ArisDisplayIdentity.swift" "$SRC/../Platform/ArisRelaunch.swift" "$SRC/../Platform/ArisBundleVersion.swift" "$SRC/../Platform/ArisAccent.swift" "$SRC/../Platform/ArisBlur.swift" \
  "$DIR/volume-tests.swift" "$SRC/../Platform/ArisVolumeRules.swift" "$SRC/../Platform/ArisVolume.swift" \
  "$DIR/helper-tests.swift" "$DIR/../Shared/ArisHelperService.swift" "$DIR/../ArisXPCHelper/ArisDisplayBrightness.swift" "$DIR/../ArisXPCHelper/ArisHelperServiceObject.swift" "$SRC/../Platform/ArisHelperClient.swift" "$SRC/../Platform/ArisBrightness.swift" \
  "$DIR/notch-geometry-tests.swift" "$SRC/../Notch/ArisNotchGeometry.swift" "$SRC/../Notch/ArisNotchShape.swift" \
  "$DIR/leaf-tests.swift" "$SRC/../Notch/ArisPanTracker.swift" "$SRC/../Platform/ArisAppIcon.swift" "$SRC/../Platform/ArisAppleScript.swift" "$SRC/../Platform/ArisStallWatch.swift" "$DIR/qa-hang-tests.swift" \
  "$DIR/preference-tests.swift" "$SRC/../Notch/ArisPreferenceTypes.swift" "$SRC/../Notch/ArisAppLanguage.swift" \
  "$DIR/drop-tests.swift" "$SRC/../Notch/ArisDragWatch.swift" "$SRC/../Notch/ArisDropTargeting.swift" \
  "$DIR/shelf-tests.swift" "$SRC/../Shelf/ArisShelfItem.swift" "$SRC/../Shelf/ArisShelfStorage.swift" "$SRC/../Shelf/ArisItemLoading.swift" "$SRC/../Shelf/ArisShelfStore.swift" "$SRC/../Shelf/ArisShelfSupport.swift" "$SRC/../Shelf/ArisSharing.swift" "$SRC/../Platform/ArisLog.swift" \
  "$DIR/music-tests.swift" "$SRC/../Music/ArisJSONLines.swift" "$SRC/../Music/ArisPlayback.swift" "$SRC/../Music/ArisMusicRules.swift" "$SRC/../Music/ArisArtworkLookup.swift" "$SRC/../Music/ArisArtworkColor.swift" "$SRC/../Music/ArisMusicSource.swift" "$SRC/../Music/ArisNowPlayingAdapter.swift" \
  "$DIR/qa-music-tests.swift" "$SRC/../Platform/ArisAppleEvents.swift" "$SRC/../Music/ArisMusicEvents.swift" \
  "$DIR/qa-wake-tests.swift" "$SRC/../Aris/ArisWakeArm.swift" \
  "$DIR/qa-overlay-tests.swift" "$SRC/../Aris/Gesture/ArisOverlayCensus.swift" "$SRC/../Aris/Gesture/ArisWindowPicker.swift" "$SRC/../Aris/Gesture/ArisWindowPickOverlay.swift" \
  "$DIR/state-tests.swift" "$SRC/../Notch/ArisNotchRules.swift" "$SRC/../Notch/ArisNotchPeek.swift" "$DIR/window-tests.swift" "$SRC/../Notch/ArisNotchWindowRules.swift" "$DIR/composition-tests.swift" "$SRC/../Notch/ArisNotchDecisions.swift" "$DIR/launch-tests.swift" "$SRC/../App/ArisLaunchRules.swift" \
  "$DIR/local-reads-tests.swift" "$DIR/../ArisTools/ArisLocalStore.swift" "$DIR/../ArisTools/ArisMessagesRead.swift" "$DIR/../ArisTools/ArisMailRead.swift" "$DIR/../ArisTools/ArisNotesRead.swift" "$DIR/../ArisTools/ArisObsidianRead.swift" "$DIR/../ArisTools/ArisFindAndMaps.swift" "$DIR/../ArisAgent/ArisLocalReadPolicy.swift" "$DIR/../ArisTools/ArisTurnGate.swift" "$DIR/../ArisAgent/ArisAgyRelay.swift" \
  "$DIR/answer-format-tests.swift" "$DIR/qa-tasks-tests.swift" "$DIR/qa-drops-tests.swift" "$SRC/../Aris/ArisPendingFiles.swift" "$SRC/../Aris/Home/ArisAnswerDocument.swift" "$DIR/../ArisTools/ArisNoteMarkdown.swift" \
  "$DIR/reader-tests.swift" "$SRC/../Aris/Home/ArisDoneFold.swift" "$SRC/../Aris/ArisReaderDocument.swift" "$DIR/../ArisAgent/ArisResultPath.swift" \
  "$DIR/edit-card-tests.swift" "$SRC/../Aris/ArisCardRevise.swift" "$DIR/../ArisAgent/ArisEditableAction.swift" \
  "$DIR/dictation-tests.swift" "$SRC/../Aris/Dictation/ArisWritingStyle.swift" "$SRC/../Aris/Dictation/ArisLearnedDictionary.swift" "$SRC/../Aris/Dictation/ArisPolishPrompt.swift" "$DIR/../ArisAgent/ArisCorrection.swift" "$DIR/../ArisAgent/ArisCaretContext.swift" "$DIR/../ArisAgent/ArisInsertText.swift" "$DIR/../ArisAgent/ArisEditWatch.swift" "$DIR/../ArisAgent/ArisFocusedField.swift" "$DIR/../ArisAgent/ArisPasteSession.swift" \
  "$DIR/dictation-copy-tests.swift" "$SRC/../Aris/Dictation/ArisDictationCopy.swift" \
  "$DIR/mcp-tests.swift" "$DIR/../ArisAgent/ArisMCPSchema.swift" "$DIR/../ArisAgent/ArisMCPPolicy.swift" "$DIR/../ArisAgent/ArisMCPConfig.swift" \
  "$DIR/../ArisAgent/ArisMCPSecrets.swift" "$DIR/../ArisAgent/ArisMCPTransport.swift" "$DIR/../ArisAgent/ArisMCPClient.swift" \
  "$DIR/../ArisAgent/ArisMCPHub.swift" "$DIR/../ArisAgent/ArisMCPCaller.swift" "$DIR/../ArisAgent/ArisMCPCards.swift" "$DIR/../ArisTools/ArisMCPRequest.swift" \
  "$DIR/judge-tests.swift" "$DIR/../ArisTools/ArisReadGate.swift" "$DIR/../ArisAgent/ArisReadJudge.swift" "$DIR/../ArisAgent/ArisAgySearch.swift" \
  "$DIR/../ArisTools/ArisWebFetch.swift" \
  "$DIR/api-brain-tests.swift" "$DIR/../ArisAgent/ArisAPIPreset.swift" "$DIR/../ArisAgent/ArisAPITransport.swift" \
  "$DIR/../ArisAgent/ArisAPIDialects.swift" "$DIR/../ArisAgent/ArisAPICatalog.swift" "$DIR/../ArisAgent/ArisAPIGate.swift" \
  "$DIR/../ArisAgent/ArisAPIHelper.swift" "$DIR/../ArisAgent/ArisAPIDriver.swift" "$DIR/../ArisAgent/ArisAPIOneShot.swift" \
  "$DIR/../ArisAgent/ArisAPIModels.swift" "$DIR/../ArisAgent/ArisAPIRoutes.swift" "$DIR/../ArisAgent/ArisAPIImageText.swift" \
  "$DIR/skills-tests.swift" "$DIR/../ArisAgent/ArisSkillFormat.swift" "$DIR/../ArisAgent/ArisSkillFolder.swift" "$DIR/../ArisAgent/ArisSkillStore.swift" \
  "$DIR/../ArisAgent/ArisSkillPrompt.swift" "$DIR/../ArisAgent/ArisSkillScript.swift" "$DIR/../ArisAgent/ArisSkillArchive.swift" "$DIR/../ArisAgent/ArisSkillLink.swift" \
  "$DIR/../ArisAgent/ArisSkillProcess.swift" "$DIR/../ArisAgent/ArisSkillSetup.swift" "$DIR/../ArisAgent/ArisSkillInstaller.swift" "$DIR/../ArisAgent/ArisSkillCheck.swift" \
  "$DIR/../ArisAgent/ArisSealedOneShot.swift" "$DIR/../ArisAgent/ArisSkillJob.swift" "$DIR/../ArisAgent/ArisSkills.swift" "$DIR/../ArisAgent/ArisSkills+Add.swift" \
  "$DIR/../ArisAgent/ArisSkillTrials.swift" "$DIR/../ArisAgent/ArisSkillTool.swift" "$DIR/../ArisTools/ArisSkillRequest.swift" \
  "$DIR/../ArisAgent/ArisSkillSandbox.swift" "$DIR/../Aris/private/Aris/Skills/ArisSkillsStatus.swift" \
  "$DIR/desktop-tests.swift" "$DIR/../ArisAgent/ArisDesktopBatch.swift" "$DIR/../ArisAgent/ArisComputerUseLedger.swift" "$DIR/../ArisAgent/ArisDesktopWords.swift" \
  "$DIR/../ArisAgent/ArisDesktopEnvelope.swift" "$DIR/../ArisAgent/ArisDesktopGate.swift" "$DIR/../ArisAgent/ArisDesktopRuntime.swift" \
  "$DIR/../ArisAgent/ArisDesktopEngine.swift" "$DIR/../ArisAgent/ArisDesktopVision.swift" "$SRC/../Aris/Desktop/ArisOperatingRules.swift" \
  "$DIR/../ArisAgent/ArisDesktopObservation.swift" "$DIR/../ArisAgent/ArisDesktopPrivacy.swift" "$DIR/../ArisAgent/ArisDesktopVerify.swift" \
  "$DIR/../ArisAgent/ArisDesktopController.swift" "$DIR/../ArisAgent/ArisDesktopActions.swift" "$DIR/../ArisAgent/ArisDesktopTextLadder.swift" \
  "$DIR/../ArisAgent/ArisDesktopLook.swift" "$DIR/../ArisAgent/ArisPeekabooCommands.swift" "$DIR/../ArisAgent/ArisComputerEngineChoice.swift" "$DIR/../ArisAgent/ArisSettingsPanes.swift" "$DIR/../ArisAgent/ArisSpawn.swift" "$DIR/../ArisAgent/ArisFileRelay.swift" \
  "$DIR/aside-tests.swift" "$DIR/../ArisAgent/ArisAside.swift" "$DIR/../ArisAgent/ArisAsideTool.swift" "$DIR/../ArisTools/ArisAsideRequest.swift" \
  "$DIR/convert-tests.swift" "$DIR/convert-gate-tests.swift" "$DIR/../ArisTools/ArisConvert.swift" "$DIR/../ArisTools/ArisConvertJobs.swift" \
  "$DIR/../ArisTools/ArisConvertImages.swift" "$DIR/../ArisTools/ArisConvertPDF.swift" "$DIR/../ArisTools/ArisConvertMedia.swift" \
  "$DIR/qa-fixes-tests.swift" "$SRC/../Aris/ArisFailure.swift" "$SRC/../Aris/ArisPanelKeys.swift" \
  "$DIR/qa-batch2-tests.swift" \
  "$DIR/qa-batch3-tests.swift" "$DIR/../ArisTools/ArisTypeReadback.swift" "$DIR/../ArisTools/ArisAppNames.swift" \
  "$DIR/qa-bug28-tests.swift" "$DIR/../ArisAgent/ArisScheduleCard.swift" \
  "$DIR/qa-batch4-tests.swift" "$SRC/../Aris/ArisUndoWords.swift" "$DIR/../ArisAgent/ArisFolderAccess.swift" \
  "$DIR/qa-followup-a-tests.swift" \
  "$DIR/qa-followup-b-tests.swift" "$DIR/../ArisTools/ArisDisplayGeometry.swift" \
  "$DIR/qa-followup-tests.swift" "$DIR/qa-final-tests.swift" "$SRC/../Aris/ArisCardWait.swift" \
  "$DIR/qa-final2-tests.swift" "$SRC/../Aris/ArisTurnWatchdog.swift" "$SRC/../Aris/ArisAttachmentText.swift" "$DIR/../ArisAgent/ArisSlowCalls.swift" "$DIR/../ArisAgent/ArisEventCard.swift" "$SRC/../Aris/ArisEventEdit.swift" "$SRC/../Calendar/ArisEventKitStore.swift" "$SRC/../Aris/ArisSaveAnswer.swift" "$SRC/../Aris/ArisUIWords.swift" "$DIR/../ArisAgent/ArisCardWords.swift" "$SRC/../Aris/ArisActionGrant.swift" "$DIR/../ArisAgent/ArisActionGrants.swift" "$DIR/../ArisAgent/ArisSaveText.swift" \
  "$DIR/qa-final3-tests.swift" \
  "$DIR/qa-b3-tests.swift" "$SRC/../Aris/Side/ArisStripLayout.swift" \
  "$DIR/side-tabs-tests.swift" "$SRC/../Aris/Side/ArisSideTab.swift" \
  "$DIR/usage-colors-tests.swift" "$SRC/../Aris/Side/ArisProviderColors.swift" \
  "$DIR/screen-need-tests.swift" "$SRC/../Aris/See/ArisScreenNeed.swift" "$DIR/../ArisAgent/ArisAgentPrompt+Screen.swift" \
  "$DIR/fix-notch-tests.swift" "$SRC/../Aris/ArisControlReply.swift" "$SRC/../Aris/Side/ArisSideEdgeRules.swift" \
  "$DIR/fix-voice-tests.swift" "$SRC/../Aris/ArisMicInterruption.swift" "$SRC/../Aris/ArisWakeHandOver.swift" "$SRC/../Aris/ArisLongTurn.swift" "$SRC/../Aris/ArisHearingLocale.swift" "$SRC/../Aris/ArisVoiceFallback.swift" \
  "$DIR/fix-tools-tests.swift" "$DIR/../ArisTools/ArisBoundedRun.swift" "$DIR/../ArisTools/ArisMessageSend.swift" "$DIR/../ArisTools/ArisEventWords.swift" "$DIR/../ArisTools/ArisExternalDisks.swift" \
  "$DIR/fix-team-tests.swift" "$DIR/../ArisAgent/ArisClaudeHookCheck.swift" "$SRC/../Aris/Team/ArisTeamSaveRule.swift" "$SRC/../Aris/Team/ArisTeammateFolder.swift" \
  "$DIR/first-run-tests.swift" "$SRC/../Aris/ArisFirstRun.swift" "$SRC/../Aris/ArisBrainChoice.swift" "$SRC/../Aris/ArisPermissionPanelRules.swift" "$SRC/../Aris/ArisUILanguage.swift" \
  "$DIR/fix-ship-tests.swift" "$DIR/../Shared/ArisBuildInfo.swift" "$DIR/../Shared/ArisBuildStamp.swift" \
  "$DIR/qa-final4-tests.swift" "$DIR/../ArisAgent/ArisOwnDataTurn.swift" "$DIR/../ArisAgent/ArisCardLedger.swift" \
  "$DIR/fix-desktop-tests.swift" "$DIR/../ArisAgent/ArisDesktopAim.swift" "$DIR/../ArisAgent/ArisChildFeed.swift" \
  "$DIR/../ArisAgent/ArisDesktopWindowNames.swift" "$DIR/../ArisAgent/ArisDesktopHonesty.swift" \
  "$DIR/fix-agent-tests.swift" "$DIR/../ArisAgent/ArisExactProcess.swift" "$DIR/../ArisAgent/ArisProgramFinder.swift" "$DIR/../ArisAgent/ArisJobBrain.swift" "$DIR/../ArisAgent/ArisAgyRules.swift" \
  "$DIR/fix-turn-tests.swift" "$SRC/../Aris/ArisIntentScope.swift" "$SRC/../Aris/ArisLocalReply.swift" "$SRC/../Aris/ArisDeadline.swift" "$SRC/../Aris/ArisTurnWatch.swift" \
  "$DIR/fix-cards-tests.swift" "$SRC/../Aris/ArisCardCover.swift" "$SRC/../Aris/ArisWaitingCards.swift" "$SRC/../Aris/Team/ArisJobLedger.swift" \
  "$DIR/security-review-tests.swift" \
  "$DIR/gate-desktop-tests.swift" "$DIR/../ArisAgent/ArisDesktopCopy.swift" \
  "$DIR/fix-leftovers-tests.swift" "$SRC/ClaudeHookRetry.swift" "$SRC/ClaudeSessionSweep.swift" "$SRC/ClaudeLimitReached.swift" \
  "$SRC/../Aris/ArisPrerequisites.swift" "$DIR/../Aris/components/Settings/ArisSettingsCopy.swift" \
  "$DIR/ai-services-tests.swift" "$DIR/../Aris/components/Settings/ArisAIServicesModel.swift" "$DIR/../Aris/components/Settings/ArisAIServicesPageModel.swift" "$DIR/../Aris/components/Settings/ArisAIServicesSheetModel.swift" "$DIR/../Aris/components/Settings/ArisAIVoices.swift" "$DIR/../ArisAgent/ArisAPIConnections.swift" \
  "$DIR/feat-progress-tests.swift" "$SRC/../Aris/Home/ArisTagTimes.swift" "$SRC/../Aris/Home/ArisStopLine.swift" "$DIR/../ArisAgent/ArisStepLine.swift" \
  "$DIR/vm-setup-tests.swift" "$SRC/../Aris/Onboarding/ArisOnboardingFront.swift" \
  "$DIR/feat-receipt-tests.swift" "$SRC/../Aris/ArisReceipt.swift" "$SRC/../Aris/ArisReceiptWords.swift" "$DIR/../ArisTools/ArisActSummary.swift" "$DIR/../ArisAgent/ArisSendJob.swift" \
  "$DIR/gate-brains-tests.swift" "$DIR/../ArisTools/ArisFileText.swift" "$DIR/../ArisAgent/ArisActionGate.swift" "$DIR/../ArisAgent/ArisTurnFallback.swift" "$DIR/../ArisAgent/ArisAgentPrompt+HandOff.swift" \
  "$DIR/vm-screen-tests.swift" "$DIR/../ArisAgent/ArisScreenRead.swift" "$DIR/../ArisAgent/ArisScreenAccess.swift" "$SRC/../Aris/See/ArisLookContext.swift" \
  "$DIR/feat-dayend-tests.swift" "$SRC/../Aris/DayEnd/ArisDayEnd.swift" "$SRC/../Aris/DayEnd/ArisDayEndCopy.swift" "$SRC/../Aris/DayEnd/ArisDayEndAsk.swift" "$SRC/../Aris/DayEnd/ArisDayEndJobs.swift" "$SRC/../Aris/DayEnd/ArisDayEndSetting.swift" "$DIR/../ArisAgent/ArisDayEndRoute.swift" \
  "$DIR/vm-usage-tests.swift" "$DIR/../ArisAgent/ArisUsageDesk.swift" "$SRC/../Aris/Side/ArisUsageTabState.swift" "$SRC/../Platform/ArisTerminationSignal.swift" "$SRC/../Aris/ArisCardListenLog.swift" "$DIR/../ArisAgent/ArisStepOutcome.swift" \
  "$DIR/gate-policy-tests.swift" "$DIR/../ArisAgent/ArisRiskPolicy+Quoting.swift" "$DIR/../ArisAgent/ArisRefusalWords.swift" "$DIR/../ArisAgent/ArisMailCard.swift" "$DIR/../ArisAgent/ArisRiskPolicy+ReadCommands.swift" "$DIR/../ArisAgent/ArisGateWords.swift" "$DIR/../ArisAgent/ArisRiskPolicy+Files.swift" \
  "$DIR/en-settings-tests.swift" \
  "$DIR/feat-quiet-tests.swift" "$SRC/../Aris/ArisQuiet.swift" "$SRC/../Aris/ArisQuietWords.swift" "$SRC/../Aris/ArisQuietGate.swift" "$SRC/../Aris/ArisQuietSettingsRows.swift" \
  "$DIR/feat-drop-tests.swift" "$SRC/../Aris/Drop/ArisDropKind.swift" "$SRC/../Aris/Drop/ArisDropGuard.swift" "$SRC/../Aris/Drop/ArisDropFile.swift" "$SRC/../Aris/Drop/ArisDropCopy.swift" "$SRC/../Aris/Drop/ArisDropChips.swift" "$SRC/../Aris/Drop/ArisDropReading.swift" \
  "$DIR/vm-english-tests.swift" "$SRC/../Aris/ArisUIDates.swift" "$SRC/../Aris/Side/ArisUsageWords.swift" "$SRC/../Aris/ArisTodoWords.swift" \
  "$SRC/../Aris/Home/ArisConfirmWords.swift" "$SRC/../Aris/Home/ArisCardEnglish.swift" "$SRC/../Aris/ArisSettingsPath.swift" "$SRC/../Aris/ArisTimerWords.swift" \
  "$DIR/feat-routines-tests.swift" "$SRC/../Aris/ArisRoutineProgress.swift" "$DIR/../ArisAgent/ArisRoutine.swift" "$DIR/../ArisAgent/ArisRoutineStore.swift" "$DIR/../ArisAgent/ArisRoutineIntent.swift" "$DIR/../ArisAgent/ArisRoutineCopy.swift" "$DIR/../ArisAgent/ArisRoutineRun.swift" "$DIR/../ArisAgent/ArisRoutineTool.swift" "$DIR/../ArisAgent/ArisRoutineTier.swift" "$DIR/../ArisTools/ArisRoutineRequest.swift" \
  "$DIR/feat-why-tests.swift" "$DIR/../ArisAgent/ArisWhyRecord.swift" "$DIR/../ArisAgent/ArisWhyBook.swift" "$DIR/../ArisAgent/ArisWhyIntent.swift" "$DIR/../ArisAgent/ArisWhyRules.swift" "$DIR/../ArisAgent/ArisWhyAnswer.swift" "$DIR/../ArisAgent/ArisWhyCopy.swift" "$DIR/../ArisAgent/ArisWhyDesk.swift" "$DIR/../ArisAgent/ArisWhyPrompt.swift" \
  "$DIR/feat-fix-tests.swift" "$SRC/../Aris/ArisFix.swift" "$SRC/../Aris/ArisFixWords.swift" "$SRC/../Aris/ArisFixDesk.swift" "$DIR/../ArisAgent/ArisFixTurns.swift" \
  "$DIR/feat-mail-tests.swift" "$DIR/../ArisTools/ArisMailMIME.swift" "$DIR/../ArisTools/ArisMailText.swift" "$DIR/../ArisTools/ArisMailFind.swift" "$DIR/../ArisTools/ArisMailStore.swift" "$DIR/../ArisTools/ArisMailReply.swift" "$DIR/../ArisAgent/ArisMailReplyCard.swift" "$DIR/../ArisAgent/ArisMailPrompt.swift" \
  "$DIR/vm2-setup-tests.swift" "$SRC/../Aris/Onboarding/ArisOnboardingLeave.swift" "$SRC/../Aris/Onboarding/ArisOnboardingFirstCapture.swift" "$SRC/../Aris/Onboarding/ArisOnboardingBrainHelp.swift" "$SRC/../Aris/Onboarding/ArisOnboardingWords.swift" \
  "$DIR/vm2-local-tests.swift" "$SRC/../Aris/ArisIntentEnglish.swift" "$SRC/../Aris/ArisRoutineStep.swift" "$DIR/../ArisAgent/ArisRoutineHandBack.swift" "$DIR/../ArisAgent/ArisWhyDeclined.swift" \
  "$DIR/vm2-settings-tests.swift" "$DIR/../Aris/components/Settings/ArisAIMenuHighlight.swift" \
  "$DIR/sec-fix-2-tests.swift" "$DIR/../ArisAgent/ArisStoredWords.swift" "$DIR/../ArisAgent/ArisCodexChange.swift" "$DIR/../ArisAgent/ArisRiskPolicy+BareNames.swift" \
  "$DIR/en-leftovers-tests.swift" "$SRC/../Aris/ArisWakeWords.swift" "$DIR/../ArisAgent/ArisSkillLanguage.swift" "$DIR/../ArisAgent/ArisClaudeJobWords.swift" "$SRC/../Aris/ArisActivityWords.swift" \
  "$DIR/vm2-notch-tests.swift" "$SRC/../Aris/Design/ArisBandMetrics.swift" "$SRC/../Notch/ArisClosedBand.swift" "$SRC/../Notch/ArisMutedMark.swift" "$SRC/../Notch/ArisNotchPointer.swift" \
  "$DIR/../ArisAgent/ArisInsertRefusal.swift" \
  "$DIR/v3-fix-tests.swift" "$SRC/../Aris/ArisUndoSteps.swift" "$SRC/../Aris/ArisPointsBack.swift" \
  "$DIR/sec-fix-3-tests.swift" "$DIR/../ArisTools/ArisTabTarget.swift" "$DIR/../ArisTools/ArisScreenTarget.swift" "$SRC/../Aris/ArisCardHold.swift" "$DIR/../Aris/components/Settings/ArisSettingsFront.swift" \
  "$DIR/../ArisAgent/ArisLookTarget.swift" "$SRC/../Aris/ArisRemindersAccess.swift" "$SRC/../Aris/ArisListenStart.swift" "$DIR/../ArisAgent/ArisGateReason.swift" \
  "$DIR/feat-2-tests.swift" "$SRC/../Aris/ArisMicPlan.swift" "$SRC/../Aris/ArisOwnOutput.swift" "$SRC/../Aris/ArisQuietSpan.swift" "$SRC/../Aris/ArisQuietHoursWords.swift" \
  "$DIR/../Aris/components/Settings/ArisSettingsCopyMore.swift" "$SRC/../Aris/Team/ArisTerminal.swift" "$SRC/../Aris/Team/ArisTerminalSetting.swift" \
  "$DIR/../ArisAgent/ArisTerminalOpener.swift" "$SRC/../Aris/Drop/ArisDropLearned.swift" "$SRC/../Aris/Drop/ArisDropLearnedSetting.swift" \
  "$DIR/dayend2-tests.swift" "$SRC/../Aris/DayEnd/ArisDayEndPlan.swift" "$SRC/../Aris/DayEnd/ArisDayEndPush.swift" \
  "$DIR/glass-tests.swift" "$DIR/glass-render/glass-contrast.swift" "$SRC/../Aris/Design/ArisGlassRecipe.swift" \
  "$DIR/settings2-tests.swift" \
  "$DIR/onboard2-tests.swift" "$SRC/../Aris/Onboarding/ArisSetupPlan.swift" "$SRC/../Aris/Onboarding/ArisRailMetrics.swift" "$SRC/../Aris/Onboarding/ArisSetupTry.swift" "$SRC/../Aris/Onboarding/ArisSetupBrainKey.swift" "$SRC/../Aris/Onboarding/ArisSetupDictation.swift" "$SRC/../Aris/Onboarding/ArisFirstTriesPlan.swift" "$SRC/../Aris/Onboarding/ArisOnboardingPreviewScore.swift" \
  "$DIR/wake2-tests.swift" "$SRC/../Aris/ArisWakeVoice.swift" "$SRC/../Aris/ArisWakeCore.swift" "$SRC/../Aris/ArisWakeRest.swift" \
  "$DIR/one-row-tests.swift" "$DIR/../Shared/ArisAgentInstall.swift" "$DIR/../ArisXPCHelper/ArisAgentInstaller.swift" "$DIR/../ArisXPCHelper/ArisAgentInstallLive.swift" "$DIR"/../ArisAgent/ArisOrigin*.swift "$DIR/../ArisAgent/ArisAppBundle.swift" "$SRC/../Aris/ArisHelperInstallWords.swift" \
  "$DIR/sec-fix-4-tests.swift" "$DIR/sec-fix-4-vouch-tests.swift" "$DIR/sec-fix-4-identity-tests.swift" "$DIR/sec-fix-4-h1-tests.swift" "$DIR/sec-fix-4-install-tests.swift" "$DIR/../Shared/ArisLoadedJob.swift" "$DIR/../ArisAgent/ArisToolsLink.swift" "$DIR/../ArisAgent/ArisProgramApproval.swift" "$DIR/../Shared/ArisSafeFiles.swift" "$DIR/../ArisAgent/ArisChildren.swift" "$DIR/../ArisAgent/ArisVouchService.swift" \
  "$DIR/glass2-tests.swift" "$SRC/../Aris/Design/ArisGlassLook.swift" \
  "$DIR/glass3-tests.swift" "$SRC/../Aris/Design/ArisGlassFallback.swift" "$SRC/../Aris/Design/ArisNotchGlassGeometry.swift" \
  "$DIR/team-quiet-tests.swift" "$SRC/../Aris/Team/ArisQuietLaunch.swift" "$DIR/../ArisAgent/ArisQuietOpener.swift" "$DIR/team-quiet-stubs.swift" \
  "$DIR/fix-5-tests.swift" "$SRC/../Aris/ArisHelperReturn.swift" "$DIR/../ArisAgent/ArisJobClaim.swift" "$SRC/../Aris/ArisReminderLists.swift" \
  "$DIR/vside-tests.swift" "$SRC/../Aris/Side/ArisSideLook.swift" "$SRC/../Aris/Team/ArisPillLook.swift" "$SRC/../Aris/ArisHistoryRestore.swift" \
  "$DIR/fx-tests.swift" "$SRC/../Aris/Currency/ArisCurrencyNames.swift" "$SRC/../Aris/Currency/ArisCurrencyMath.swift" "$SRC/../Aris/Currency/ArisCurrencyAsk.swift" "$SRC/../Aris/Currency/ArisCurrencyCard.swift" "$SRC/../Aris/Currency/ArisCurrencyCopy.swift" "$DIR/../ArisTools/ArisCurrency.swift" "$DIR/../ArisAgent/ArisCurrencyRoute.swift" "$DIR/../ArisTools/ArisFetch.swift" \
  "$DIR/vnotch-tests.swift" "$SRC/../Notch/ArisVNotch.swift" "$SRC/../Aris/Home/ArisPromptEdit.swift" "$SRC/../Aris/ArisCardRead.swift" \
  "$DIR/siri-look-tests.swift" "$SRC/../Aris/SiriLook/ArisSiriLook.swift" \
  "$DIR/hooks-fast-tests.swift" "$SRC/ClaudeHookWire.swift" "$SRC/ClaudeHookRoute.swift" "$SRC/ClaudeHookHold.swift" "$SRC/ClaudeHookConnection.swift" "$SRC/ClaudeHookServer.swift" "$SRC/ClaudeStore+Hooks.swift" \
  "$SRC/../Aris/Drop/ArisDropTextAhead.swift" "$SRC/../Platform/ArisFileIcons.swift" \
  "$DIR/automode-tests.swift" "$DIR/../ArisAgent/ArisAutoCheck.swift" "$DIR/../ArisAgent/ArisAutoScope.swift" "$DIR/../ArisAgent/ArisOwnerWords.swift" \
  "$DIR/../ArisAgent/ArisAutoMode.swift" "$DIR/../ArisAgent/ArisAutoHandOff.swift" "$DIR/../ArisAgent/ArisAutoMarks.swift" \
  "$DIR/../ArisAgent/ArisAutoCheckLive.swift" "$SRC/../Aris/ArisStoppedCopy.swift" \
  "$DIR/automode-int-tests.swift" \
  "$DIR/vnotch-vm2-tests.swift" "$SRC/../Aris/Home/ArisFieldFocus.swift" "$SRC/../Notch/ArisBandEar.swift" \
  "$DIR/workmem-tests.swift" "$DIR/../ArisAgent/ArisWorkMemory.swift" "$DIR/../ArisAgent/ArisWorkMemorySteps.swift" "$DIR/../ArisAgent/ArisWorkMemoryStore.swift" "$DIR/../ArisAgent/ArisWorkMemoryRecall.swift" "$DIR/../ArisAgent/ArisWorkLessons.swift" "$DIR/../ArisAgent/ArisWorkDesk.swift" "$DIR/../ArisAgent/ArisWorkTitle.swift" "$DIR/../ArisAgent/ArisWorkWords.swift" "$DIR/../ArisAgent/ArisWorkIntent.swift" "$DIR/../ArisAgent/ArisWorkPrompt.swift" "$SRC/../Aris/ArisWorkSettings.swift" \
  "$DIR/memory-import-tests.swift" "$DIR/../ArisAgent/ArisMemoryImport.swift" "$DIR/../ArisAgent/ArisMemoryImportStore.swift" "$SRC/../Aris/ArisMemoryImportBoard.swift" \
  "$DIR/memory-import-motion-tests.swift" "$SRC/../Aris/ArisMemoryImportPacing.swift" \
  "$DIR/workmem-sec-tests.swift" "$DIR/../ArisAgent/ArisDataExport.swift" "$SRC/../Aris/ArisMemoryImportRowDetail.swift" \
  "$DIR/fix-6-tests.swift" "$DIR/../ArisAgent/ArisFrontNow.swift" "$DIR/../ArisAgent/ArisFrontLive.swift" "$SRC/../Aris/ArisUserApp.swift" "$DIR/../ArisAgent/ArisAPIFailureWords.swift" "$DIR/../Aris/components/Settings/ArisAIKeyChoice.swift" "$SRC/../Aris/ArisRouterKeyHealth.swift" \
  "$DIR/hook-wedge-tests.swift" \
  "$DIR/fix-7-tests.swift" "$SRC/../Aris/ArisOutsideItems.swift" "$DIR/../ArisAgent/ArisAutoPlaces.swift" "$SRC/../Calendar/ArisOwnPlace.swift" \
  "$DIR/fix-8-tests.swift" "$DIR/../ArisAgent/ArisHelperListing.swift" "$SRC/../Aris/ArisCalendarCardDay.swift" "$DIR/../ArisAgent/ArisSendClaim.swift" \
  "$DIR/themes-tests.swift" "$SRC/../Aris/Design/ArisTextBacking.swift" "$DIR/../Aris/components/Settings/ArisNotchLookSetting.swift" \
  "$SRC/../Notch/ArisRestStar.swift" "$SRC/../Aris/Design/ArisNotchTheme.swift"
# The tests keep every UserDefaults suite they make (aris-*-tests) in a throwaway folder (testSuiteName, by its path:
# CFFIXED_USER_HOME alone doesn't stop cfprefsd writing to ~/Library/Preferences, and a path whose folder is named
# Library/Preferences is taken as the user's own domain), never in the user's real Preferences.
# A run that makes or changes any aris-*.plist there fails, whatever the tests said.
PREFS="$HOME/Library/Preferences"
TEST_HOME="$(mktemp -d)"
mkdir -p "$TEST_HOME/Library/Preferences"
touch "$TEST_HOME/started"
STATUS=0
# ARIS_TEST_SANDBOX=<profile.sb>: the compiled tests run under sandbox-exec (swiftc's macro server can't run inside one).
if [ -n "${ARIS_TEST_SANDBOX:-}" ]; then
  CFFIXED_USER_HOME="$TEST_HOME" ARIS_TEST_PREFS="$TEST_HOME/prefs" sandbox-exec -D HOME="$HOME" -f "$ARIS_TEST_SANDBOX" "$OUT" || STATUS=1
else
  CFFIXED_USER_HOME="$TEST_HOME" ARIS_TEST_PREFS="$TEST_HOME/prefs" "$OUT" || STATUS=1
fi
LEAKED="$(find "$PREFS" -maxdepth 1 -name 'aris-*.plist' -newer "$TEST_HOME/started" -exec basename {} \; 2>/dev/null || true)"
rm -rf "$TEST_HOME"
if [ -n "$LEAKED" ]; then
  echo "PREFS LEAK: the tests wrote into $PREFS:"; printf '  %s\n' $LEAKED; exit 1
fi
[ "$STATUS" -eq 0 ] || { echo "FAILED OR CRASHED"; exit 1; }
