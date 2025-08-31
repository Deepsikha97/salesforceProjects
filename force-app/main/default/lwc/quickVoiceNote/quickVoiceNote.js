import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import saveVoiceNote from "@salesforce/apex/QuickVoiceNoteController.saveVoiceNote";

export default class QuickVoiceNote extends LightningElement {
	recordLabel = "Start Recording";
	isRecording = false;
	@api recordId;
	transcript = "";
	finalTranscript = ""; // confirmed text
	interimTranscript = ""; // temporary text
	editableTranscript = ""; // bound to textarea
	recognition;

	connectedCallback() {
		const SpeechRecognition =
			window.SpeechRecognition || window.webkitSpeechRecognition;

		if (SpeechRecognition) {
			this.recognition = new SpeechRecognition();
			this.recognition.interimResults = true;
			this.recognition.continuous = true;
			this.recognition.lang = "en-US";

			this.recognition.onresult = (event) => {
				let interim = "";

				for (let i = event.resultIndex; i < event.results.length; i++) {
					const transcriptPart = event.results[i][0].transcript;

					if (event.results[i].isFinal) {
						this.finalTranscript += transcriptPart + " ";
					} else {
						interim += transcriptPart; // accumulate instead of overwrite
					}
				}

				this.interimTranscript = interim.trim();
				this.editableTranscript = (
					this.finalTranscript + this.interimTranscript
				).trim();
			};

			this.recognition.onend = () => {
				if (this.isRecording) {
					this.recognition.start(); // auto-restart if still recording
				}
			};
		}
	}

	toggleRecording() {
		if (!this.recognition) {
			this.showToast(
				"Error",
				"Speech Recognition not supported in this browser.",
				"error"
			);
			return;
		}

		if (this.isRecording) {
			this.recognition.stop();
		} else {
			this.transcript = "";
			this.recognition.start();
		}
		this.isRecording = !this.isRecording;
		this.recordLabel = this.isRecording ? "Stop Recording" : "Start Recording";
	}

	handleTranscriptChange(event) {
		this.editableTranscript = event.target.value;
	}

	saveNote(){
		saveVoiceNote({ transcript: this.editableTranscript, recordId: this.recordId })
			.then(() => {
				this.showToast("Success", "Voice note saved successfully.", "success");
				this.finalTranscript = "";
				this.interimTranscript = "";
				this.editableTranscript = "";
			})
			.catch((error) => {
				this.showToast("Error", error.body.message, "error");
			});
	}

	showToast(title, message, variant) {
		this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
	}
}