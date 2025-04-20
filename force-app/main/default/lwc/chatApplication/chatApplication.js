import { LightningElement, track, wire, api } from "lwc";
import sendMessage from "@salesforce/apex/ChatPublisher.sendMessage";
import { subscribe, unsubscribe, onError } from "lightning/empApi";

export default class ChatApplication extends LightningElement {
  messageInput = null;
  messages = [];
  channelName = "/event/Chat_Message__e";
  sender = "User_" + Math.floor(Math.random() * 1000); // Basic sender ID

  connectedCallback() {
    this.registerErrorListener();
    this.handleSubscribe();
  }

  renderedCallback() {
    // Inject sanitized HTML into each rich text message
    const messageDivs = this.template.querySelectorAll('.msg-text');
    messageDivs.forEach((div, index) => {
        const msg = this.messages[index];
        if (msg && msg.text) {
            div.innerHTML = msg.text;
        }
    });
}


  registerErrorListener() {
    onError((error) => {
      console.error("Streaming API error:", error);
    });
  }

  handleSubscribe() {
    subscribe(this.channelName, -1, (event) => {
      const rawTimestamp = event.data.payload.TimeStamp__c;
      const formattedTime = new Date(rawTimestamp).toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit"
      });
      const newMessage = {
        sender: event.data.payload.Sender__c,
        text: event.data.payload.Message__c,
        timestamp: formattedTime,
        senderClass:
          event.data.payload.Sender__c === this.sender
            ? "msg msg-right"
            : "msg msg-left"
      };
      console.log("Received event:", JSON.stringify(newMessage));
      this.messages = [...this.messages, newMessage];
    }).then((response) => {
      console.log("Subscribed to channel:", response.channel);
      this.subscription = response;
      console.log("Subscription response:", JSON.stringify(response));
    });
  }

  handleInputChange(event) {
    this.messageInput = event.target.value;
    console.log("Text Input:", this.messageInput);
  }

  handleSend() {
    console.log("Submit Button Clicked");
    console.log("Text Input:", this.messageInput);
    if (this.messageInput.trim() === "") {
      console.log("Text Input is empty");
      return;
    } else {
      const cleanText = this.sanitizeHtml(this.messageInput);
      console.log("Sending message:", cleanText);
      sendMessage({ sender: this.sender, message: cleanText })
        .then(() => {
          console.log("Message sent successfully");
          this.messages.push(cleanText);
          this.messageInput = null;
        })
        .catch((error) => {
          console.error("Error sending message:", error);
        });
    }
  }

  sanitizeHtml(input) {
    const div = document.createElement("div");
    div.innerHTML = input;

    // Strip out any <script> or <style> tags or dangerous attributes
    const allowedTags = [
      "B",
      "I",
      "U",
      "STRONG",
      "EM",
      "BR",
      "A",
      "P",
      "DIV",
      "SPAN"
    ];
    const elements = div.querySelectorAll("*");

    elements.forEach((el) => {
      if (!allowedTags.includes(el.tagName)) {
        el.replaceWith(...el.childNodes);
      }

      // Remove all event attributes (like onclick)
      [...el.attributes].forEach((attr) => {
        if (attr.name.startsWith("on")) {
          el.removeAttribute(attr.name);
        }
      });
    });

    return div.innerHTML;
  }
}
