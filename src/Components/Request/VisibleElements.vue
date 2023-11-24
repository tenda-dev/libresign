<template>
	<NcModal v-if="modal"
		class="view-sign-detail"
		app-name="libresign"
		@close="closeModal">
		<div class="sign-details">
			<h2>
				{{ document.name }}
				<br>
				<Chip :state="isDraft ? 'warning' : 'default'">
					{{ statusLabel }}
				</Chip>
			</h2>
			<p>
				<small>
					{{ t('libresign', 'Select each signer to define their signature positions') }}
				</small>
			</p>
			<Sidebar class="view-sign-detail--sidebar"
				:signers="signers"
				event="libresign:visible-elements-select-signer">
				<button v-if="isDraft" class="primary publish-btn" @click="publish">
					{{ t('libresign', 'Request') }}
				</button>

				<button v-if="canSign" class="primary publish-btn" @click="goToSign">
					{{ t('libresign', 'Sign') }}
				</button>
			</Sidebar>
		</div>
		<div class="image-page">
			<!-- <canvas ref="canvas" :width="page.resolution.w" :height="page.resolution.h" /> -->
			<!-- <div :style="{ width: `${page.resolution.w}px`, height: `${page.resolution.h}px`, background: 'red' }">
				<img :src="page.url">
			</div> -->
			<PageNavigation v-model="currentSigner.element.coordinates.page"
				:pages="document.pages"
				:width="pageDimensions.css.width" />
			<div class="image-page--main">
				<div class="image-page--container"
					:style="{ '--page-img-w': pageDimensions.css.width, '--page-img-h': pageDimensions.css.height }">
					<DragResize v-if="hasSignerSelected"
						parent-limitation
						:is-active="true"
						:is-resizable="true"
						:w="currentSigner.element.coordinates.width"
						:h="currentSigner.element.coordinates.height"
						:x="currentSigner.element.coordinates.left"
						:y="currentSigner.element.coordinates.top"
						@resizing="resize"
						@dragging="resize">
						<div class="image-page--element">
							{{ currentSigner.displayName }}
						</div>
						<div class="image-page--action">
							<button class="primary" @click="saveElement">
								{{ t('libresign', editingElement ? 'Update' : 'Save') }}
							</button>
						</div>
					</DragResize>
					<img ref="img" :src="page.url">
				</div>
			</div>
		</div>
	</NcModal>
</template>

<script>
import { showError, showSuccess } from '@nextcloud/dialogs'
import axios from '@nextcloud/axios'
import { generateOcsUrl } from '@nextcloud/router'
import { loadState } from '@nextcloud/initial-state'
import DragResize from 'vue-drag-resize'
import { get, pick, find, map, cloneDeep, isEmpty } from 'lodash-es'
import NcModal from '@nextcloud/vue/dist/Components/NcModal.js'
import { subscribe } from '@nextcloud/event-bus'
import { service as signService, SIGN_STATUS } from '../../domains/sign/index.js'
import Sidebar from './SignDetail/partials/Sidebar.vue'
import PageNavigation from './SignDetail/partials/PageNavigation.vue'
import { showResponseError } from '../../helpers/errors.js'
import { SignatureImageDimensions } from '../Draw/index.js'
import Chip from '../Chip.vue'

const emptyElement = () => {
	return {
		coordinates: {
			page: 1,
			left: 100,
			top: 100,
			height: SignatureImageDimensions.height,
			width: SignatureImageDimensions.width,
		},
		elementId: 0,
	}
}

const emptySignerData = () => ({
	signed: null,
	displayName: '',
	fullName: null,
	me: false,
	signRequestId: 0,
	email: '',
	element: emptyElement(),
})

const deepCopy = val => JSON.parse(JSON.stringify(val))

export default {
	name: 'VisibleElements',
	components: {
		NcModal,
		DragResize,
		Sidebar,
		PageNavigation,
		Chip,
	},
	props: {
		file: {
			type: Object,
			default: () => {},
			require: true,
		},
	},
	data() {
		return {
			canRequestSign: loadState('libresign', 'can_request_sign'),
			signers: [],
			document: {
				id: '',
				name: '',
				signers: [],
				pages: [],
				visibleElements: [],
			},
			modal: false,
			currentSigner: emptySignerData(),
		}
	},
	computed: {
		pageIndex() {
			return this.currentSigner.element.coordinates.page - 1
		},
		canSign() {
			if (this.status !== SIGN_STATUS.ABLE_TO_SIGN) {
				return false
			}

			return !isEmpty(this.signerFileUuid)
		},
		status() {
			return Number(get(this.document, 'status', -1))
		},
		statusLabel() {
			return get(this.document, 'statusText', '')
		},
		isDraft() {
			return this.status === SIGN_STATUS.DRAFT
		},
		page() {
			return this.document.pages[this.pageIndex] || {
				url: '',
				resolution: {
					h: 0,
					w: 0,
				},
			}
		},
		pageDimensions() {
			const { w, h } = this.page.resolution
			return {
				height: h,
				width: w,
				css: {
					height: `${Math.ceil(h)}px`,
					width: `${Math.ceil(w)}px`,
				},
			}
		},
		hasSignerSelected() {
			return this.currentSigner.signRequestId !== 0
		},
		editingElement() {
			return this.currentSigner.element.elementId > 0
		},
		signerFileUuid() {
			return get(this.document, ['settings', 'signerFileUuid'])
		},
	},
	mounted() {
		subscribe('libresign:show-visible-elements', this.showModal)
		subscribe('libresign:visible-elements-select-signer', this.onSelectSigner)
	},
	methods: {
		showModal() {
			if (!this.canRequestSign) {
				return
			}
			this.modal = true
			this.loadDocument()
		},
		closeModal() {
			this.modal = false
		},
		onError(err) {
			if (err.response) {
				return showResponseError(err.response)
			}

			return showError(err.message)
		},
		updateSigners() {
			const { signRequestId } = this.currentSigner

			this.currentSigner = emptySignerData()

			const [signers, visibleElements] = deepCopy([this.document.signers, this.document.visibleElements])

			this.signers = map(signers, signer => {
				const element = find(visibleElements, (el) => {
					return el.signRequestId === signer.signRequestId
				})

				const row = {
					...signer,
					element: emptyElement(),
				}

				if (element) {
					const coordinates = pick(element.coordinates, ['top', 'left', 'width', 'height', 'page'])

					row.element = {
						elementId: element.elementId,
						coordinates,
					}
				}

				return row
			})

			if (signRequestId === 0) {
				return
			}

			const current = this.signers.find(signer => signer.signRequestId === signRequestId)

			this.onSelectSigner({ ...current })
		},
		resize(newRect) {
			const { coordinates } = this.currentSigner.element

			this.currentSigner.element.coordinates = {
				...coordinates,
				...newRect,
			}
		},
		onSelectSigner(signer) {
			const page = this.pageIndex + 1

			this.currentSigner = emptySignerData()
			this.currentSigner = cloneDeep(signer)

			if (signer.element.elementId === 0) {
				this.currentSigner.element.coordinates.page = page
			}
		},
		goToSign() {
			const route = this.$router.resolve({ name: 'SignPDF', params: { uuid: this.signerFileUuid } })

			window.location.href = route.href
		},
		async publish() {
			const allow = confirm(t('libresign', 'Request signatures?'))

			if (!allow) {
				return
			}

			try {
				await signService.changeRegisterStatus(this.document.fileId, SIGN_STATUS.ABLE_TO_SIGN)
				this.loadDocument()
			} catch (err) {
				this.onError(err)
			}
		},
		async loadDocument() {
			try {
				this.signers = []
				this.document = await axios.get(generateOcsUrl(`/apps/libresign/api/v1/file/validate/file_id/${this.file.nodeId}`))
				this.document = this.document.data
				this.updateSigners()
			} catch (err) {
				this.onError(err)
			}
		},
		async saveElement() {
			const { element, signRequestId } = this.currentSigner

			const payload = {
				coordinates: {
					...element.coordinates,
					page: element.coordinates.page,
				},
				type: 'signature',
				signRequestId,
			}

			try {
				this.editingElement
					? await axios.patch(generateOcsUrl(`/apps/libresign/api/v1/file-element/${this.file.uuid}/${element.elementId}`), payload)
					: await axios.post(generateOcsUrl(`/apps/libresign/api/v1/file-element/${this.file.uuid}`), payload)
				showSuccess(t('libresign', 'Element created'))

				this.loadDocument()
			} catch (err) {
				this.onError(err)
			}
		},
	},
}
</script>

<style lang="scss" scoped>
.sign-details {
	margin-left: 5px;
}

.view-sign-detail {
	&--sidebar {
		width: 300px;
	}
	overflow: auto;
}

.image-page {
	width: 100%;
	margin: 0.5em;
	&--main {
		position: relative;
	}
	&--element {
		width: 100%;
		height: 100%;
		display: flex;
		position: absolute;
		cursor: grab;
		background: rgba(0, 0, 0, 0.3);
		color: #FFF;
		font-weight: bold;
		justify-content: space-around;
		align-items: center;
		flex-direction: row;
		&:active {
			cursor: grabbing;
		}
	}
	&--action {
		width: 100%;
		position: absolute;
		top: 100%;
	}
	&--container {
		border-color: #000;
		border-style: solid;
		border-width: thin;
		width: var(--page-img-w);
		height: var(--page-img-h);
		left: 0;
		top: 0;
		&, img {
			user-select: none;
			outline: 0;
		}
		img {
			max-width: 100%;
		}
	}
}

.publish-btn {
	width: 100%;
}
</style>