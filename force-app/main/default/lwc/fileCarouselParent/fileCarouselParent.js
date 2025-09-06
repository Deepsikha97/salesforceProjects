import { LightningElement, api, wire, track } from 'lwc';
import getFiles from '@salesforce/apex/FileController.getFiles';

export default class FileCarouselParent extends LightningElement {
    @api recordId; // when placed on a record page, platform supplies this
    @track files = [];
    @track error;

    @wire(getFiles, { recordId: '$recordId' })
    wiredFiles({ error, data }) {
        if (data) {
            // data already has VersionId (from Apex wrapper)
            this.files = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.files = [];
            // helpful console log for debugging
            // eslint-disable-next-line no-console
            console.error('Error fetching files', error);
        }
    }
}