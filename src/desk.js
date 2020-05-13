import EventEmitter from 'events'
import schedule from 'node-schedule'

export default class Desk extends EventEmitter {
  static services() {
    return {
      position: {
        id: '99fa0020338a10248a49009c0215f78a',
        characteristicId: '99fa0021338a10248a49009c0215f78a',
      },
      control: {
        id: '99fa0001338a10248a49009c0215f78a',
        characteristicId: '99fa0002338a10248a49009c0215f78a',
      },
    }
  }

  static control() {
    return {
      up: Buffer.from('4700', 'hex'),
      down: Buffer.from('4600', 'hex'),
      stop: Buffer.from('FF00', 'hex'),
    }
  }

  /**
   * 
   * @param {import('@abandonware/noble').Peripheral} peripheral
   * * @param {int} positionOffset
   */
  constructor(peripheral, positionOffset, positionMax) {
    super()

    this.peripheral = peripheral
    this.positionOffset = positionOffset
    this.position = positionOffset
    this.positionMax = positionMax
    this.shouldDisconnect = false
    this.isMoving = false

    this.isConnected = false
    this.peripheral.on('connect', () => {
      this.isConnected = true
    })
    this.peripheral.on('disconnect', () => {
      this.isConnected = false
      this.reconnect()
    })

    this.connect()
  }

  disconnect() {
    this.shouldDisconnect = true
    this.peripheral.disconnectAsync().catch(() => {
      // We don't care
    })
  }

  reconnect() {
    if (this.shouldDisconnect) {
      return
    }

    schedule.scheduleJob(Date.now() + 5000, () => {
      this.connect()
    })
  }

  connect() {
    this.ensureConnection().catch((err) => {
      console.log('failed to connect to desk: ' + err)
      this.reconnect()
    })
  }

  async ensureConnection() {
    if (this.isConnected) {
      return
    }

    if (this.shouldDisconnect) {
      throw "disconnected"
    }

    await this.peripheral.connectAsync()

    const { characteristics } = await this.peripheral.discoverSomeServicesAndCharacteristicsAsync([
      Desk.services().position.id,
      Desk.services().control.id,
    ], [
      Desk.services().position.characteristicId,
      Desk.services().control.characteristicId,
    ])
    
    const positionChar = characteristics.find(char => char.uuid == Desk.services().position.characteristicId)
    if (!positionChar) {
      throw 'Missing position service'
    }

    const data = await positionChar.readAsync()
    this.updatePosition(data)

    positionChar.on('data', async (data) => {
      this.updatePosition(data)
    })
    await positionChar.notifyAsync(true)

    const controlChar = characteristics.find(char => char.uuid == Desk.services().control.characteristicId)
    if (!controlChar) {
      throw 'Missing control service'
    }

    this.positionChar = positionChar
    this.controlChar = controlChar
  }

  async readPosition() {
    await this.ensureConnection()
    const data = await this.positionChar.readAsync()
    this.updatePosition(data)
  }

  updatePosition(data) {
    const position = this.positionOffset + (data.readInt16LE() / 100)
    if (this.position == position) {
      return
    }

    this.position = position
    this.emit('position', this.position)
  }

  /**
   * @param {Int} position 
   */
  async moveTo(targetPosition) {
    await this.stopMoving()

    if (targetPosition < this.positionOffset || targetPosition > this.positionOffset + this.positionMax) {
      return
    }

    if (Math.abs(this.position - targetPosition) <= 1) {
      return
    }

    this.movingPromise = this.performMoveTo(targetPosition)
    await this.movingPromise
  }

  async performMoveTo(targetPosition) {
    this.isMoving = true

    const isMovingUp = targetPosition > this.position
    const stopThreshold = 1
    
    try {
      while (
        this.isMoving &&
        ((isMovingUp && this.position + stopThreshold < targetPosition) ||
        (!isMovingUp && this.position - stopThreshold > targetPosition))
      ) {
        await this.ensureConnection()
        await this.controlChar.writeAsync(isMovingUp ? Desk.control().up : Desk.control().down, false)
        
        await new Promise(resolve => setTimeout(resolve, 50))
        await this.readPosition()
      }

      await this.controlChar.writeAsync(Desk.control().stop, false)
      this.isMoving = false

    } catch (err) {
      this.isMoving = false
      throw err
    }
  }

  async stopMoving() {
    this.isMoving = false
    if (this.movingPromise) {
      await this.movingPromise
    }
  }
}