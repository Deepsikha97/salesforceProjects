import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class FilePreviewCarousel extends NavigationMixin(LightningElement) {
    @api files = [];
    @track currentIndex = 0;
    @track isSlideshow = false;
    slideshowInterval;
    isModalOpen = false;

    get currentFile() {
        return this.files && this.files.length ? this.files[this.currentIndex] : null;
    }

    get fileType() {
        if (!this.currentFile || !this.currentFile.FileExtension) return 'other';
        const ext = (this.currentFile.FileExtension || '').toLowerCase();
        if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp'].includes(ext)) return 'image';
        if (ext === 'pdf') return 'pdf';
        if (['mp4', 'webm', 'ogg', 'mov'].includes(ext)) return 'video';
        if (['mp3', 'wav', 'm4a'].includes(ext)) return 'audio';
        return 'other';
    }

    get isImage() { return this.fileType === 'image'; }
    get isPDF() { return this.fileType === 'pdf'; }
    get isVideo() { return this.fileType === 'video'; }
    get isAudio() { return this.fileType === 'audio'; }
    get isOther() { return this.fileType === 'other'; }

    get slideshowIcon() {
        return this.isSlideshow ? 'utility:pause' : 'utility:play';
    }

    get pagerText() {
        if (this.currentFile && this.files.length > 0) {
            return `${this.currentIndex + 1} of ${this.files.length}`;
        }
        return '';
    }

    // direct download URL for images, videos, audio, others
    get fileUrl() {
        if (!this.currentFile) return '';
        if (this.isPDF) {
            // preview PDF safely
            return `/lightning/r/ContentDocument/${this.currentFile.ContentDocumentId}/view`;
        }
        return this.currentFile.VersionId
            ? `/sfc/servlet.shepherd/version/download/${this.currentFile.VersionId}`
            : '';
    }

    // PDF thumbnail or image/video preview
    get displayUrl() {
        if (!this.currentFile) return '';

        if (this.isPDF && this.currentFile.VersionId) {
            // renditionDownload thumbnail URL
            return `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${this.currentFile.VersionId}`;
        }

        return this.fileUrl; // images, video, audio
    }

    prev() { this._goToIndex(this.currentIndex - 1); }
    next() { this._goToIndex(this.currentIndex + 1); }

    _goToIndex(newIndex) {
    const total = this.files.length;
    // Wrap around the carousel
    this.currentIndex = (newIndex + total) % total;
}

    downloadFile() {
        if (!this.fileUrl) return;
        window.open(this.fileUrl, '_blank');
    }

    previewFile() {
        if (!this.currentFile?.ContentDocumentId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: this.currentFile.ContentDocumentId }
        });
    }

    openModal() { this.isModalOpen = true; }
    closeModal() { this.isModalOpen = false; }

    toggleSlideshow() {
        if (this.isSlideshow) {
            clearInterval(this.slideshowInterval);
            this.slideshowInterval = null;
            this.isSlideshow = false;
        } else {
            if (!this.files.length) return;
            this.isSlideshow = true;
            this.slideshowInterval = setInterval(() => { this.next(); }, 2000);
        }
    }

    disconnectedCallback() {
        if (this.slideshowInterval) clearInterval(this.slideshowInterval);
    }
}