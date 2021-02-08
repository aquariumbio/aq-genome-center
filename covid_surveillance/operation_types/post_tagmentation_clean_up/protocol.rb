# typed: false
# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Small Instruments/Centrifuges'
needs 'Small Instruments/Shakers'
needs 'Standard Libs/Units'
needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Covid Surveillance/CovidSurveillanceHelper'
needs 'Liquid Robot Helper/RobotHelper'

needs 'Composition Libs/Composition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'PCR Protocols/RunThermocycler'

needs 'Kits/KitContents'

needs 'Consumable Libs/Consumables'
needs 'Consumable Libs/ConsumableDefinitions'

class Protocol
  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Centrifuges
  include Shakers
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper
  include CompositionHelper
  include CollectionTransfer
  include CollectionActions
  include RunThermocycler
  include CovidSurveillanceHelper
  include KitContents
  include ConsumableDefinitions

#========== Composition Definitions ==========#
  POST_TAG_KIT = 'Post Tagmentation Clean Up Kit'


  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         suggested_ot: PLATE_384_WELL
       }
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[AREA_SEAL],
        qty: 1, units: 'Each'
      }
    ]
  end

########## DEFAULT PARAMS ##########

# Default parameters that are applied equally to all operations.
#   Can be overridden by:
#   * Associating a JSON-formatted list of key, value pairs to the `Plan`.
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
#
def default_job_params
  {
  }
end

# Default parameters that are applied to individual operations.
#   Can be overridden by:
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
#
def default_operation_params
  {
    mosquito_robot_program: 'Post Tagmentation Clean Up',
    mosquito_robot_model: Mosquito::MODEL,
    dragonfly_robot_program: 'TWB_HT',
    dragonfly_robot_program2: 'ST2_HT',
    dragonfly_robot_model: Dragonfly::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 500, units: TIMES_G) },
    incubation_params: { time: create_qty(qty: 5, units: MINUTES),
                         temperature: create_qty(qty: 'room temperature',
                                                 units: '') },
    thermocycler_model: TestThermocycler::MODEL,
    program_name: 'CDC_TaqPath_CG',
    qpcr: true
  }
end

########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    operations.each do |op|
      set_up_test(op) if debug
      op.pass(POOLED_PLATE)

      required_reactions = create_qty(qty: op.input(POOLED_PLATE).collection.parts.length,
                                      units: 'rxn')

      temporary_options = op.temporary[:options]

      composition, consumables, _kit_ = setup_kit_composition(
        kit_sample_name: POST_TAG_KIT,
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumable_data
      )

      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
      plate = composition.input(POOLED_PLATE).item
      plate_display = composition.input(POOLED_PLATE).display_name

      show_retrieve_parts(composition.components + consumables.consumables)

      vortex_list = reject_components(
        list_of_rejections: [POOLED_PLATE],
        components: composition.components
      )


      show_block_1 = []

      show_block_1.append(
        {
          display: seal_plate(
            [plate_display], seal: consumables.input(AREA_SEAL)
          ),
          type: 'note'
        }
      )

      show_block_1.append(
        {
          display: shake(items: vortex_list.map(&:display_name),
                         type: Vortex::NAME),
          type: 'note'
        }
      )

      show_block_1.append(
        { 
          display: spin_down(
            items: [plate_display],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: temporary_options[:centrifuge_parameters][:time]
          ),
          type: 'note'
        }
      )

      association_map = one_to_one_association_map(from_collection: plate)

      drgprogram = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:dragonfly_robot_program]
      )

      drgprogram2 = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:dragonfly_robot_program2]
      )

      drgrobot = LiquidRobotFactory.build(
        model: temporary_options[:dragonfly_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:mosquito_robot_program]
      )

      robot = LiquidRobotFactory.build(
        model: temporary_options[:mosquito_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      show_block_1.append(
        use_robot(program: drgprogram,
                  robot: drgrobot,
                  items: [plate_display,
                          composition.input(ST2_HT).display_name])
      )

      associate_transfer_item_to_collection(
        from_item: composition.input(ST2_HT).item,
        to_collection: plate,
        association_map: association_map,
        transfer_vol: composition.input(ST2_HT).volume_hash
      )

      show_block_2 = []

      show_block_2.append(
        {
          display: seal_plate(
            [plate_display], seal: consumables.input(AREA_SEAL)
          ),
          type: 'note'
        }
      )

      show_block_1.append(
        {
          display: shake(items: vortex_list.map(&:display_name),
                         type: Vortex::NAME),
          type: 'note'
        }
      )

      show_block_2.append(
        {
          display: show_incubate_items(
            items: [plate_display],
            time: temporary_options[:incubation_params][:time],
            temperature: temporary_options[:incubation_params][:temperature]
          ),
          type: 'note'
        }
      )

      show_block_2.append(
        { 
          display: spin_down(
            items: [plate_display],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: temporary_options[:centrifuge_parameters][:time]
          ),
          type: 'note'
        }
      )

      show_block_2.append(
        { display: place_on_magnet(plate_display),
          type: 'note' }
      )

      show_block_2.append(
        use_robot(
          program: program,
          robot: robot,
          items: [plate_display]
        )
      )

      show_block_3 = []
      show_block_3.append(use_robot(
        program: drgprogram2,
        robot: drgrobot,
        items: [plate_display, composition.input(TWB_HT).display_name]
      ))

      associate_transfer_item_to_collection(
        from_item: composition.input(TWB_HT).item,
        to_collection: plate,
        association_map: association_map,
        transfer_vol: composition.input(TWB_HT).volume_hash
      )

      show_block_3.append(
        {
          display: seal_plate(
            [plate_display],
            seal: consumables.input(AREA_SEAL)
          ),
          type: 'note'
        }
      )

      show_block_3.append(
        {
          display: shake(items: vortex_list.map(&:display_name),
                         type: Vortex::NAME),
          type: 'note'
        }
      )

      show_block_3.append(
        { 
          display: spin_down(
            items: [plate_display],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: temporary_options[:centrifuge_parameters][:time]
          ),
          type: 'note'
        }
      )

      show_block_3.append({ display: place_on_magnet(plate_display),
                            type: 'note' })

      show_block_2.append( 
        use_robot(
          program: program,
          robot: robot,
          items: [plate_display]
        )
      )

      show_block_4 = []
      show_block_4.append(
        use_robot(
          program: drgprogram2,
          robot: drgrobot,
          items: [plate_display, composition.input(TWB_HT).display_name]
        )
      )

      associate_transfer_item_to_collection(
        from_item: composition.input(TWB_HT).item,
        to_collection: plate,
        association_map: association_map,
        transfer_vol: composition.input(TWB_HT).volume_hash
      )

      show_block_4.append(
        {
          display: seal_plate(
            [plate_display], seal: consumables.input(AREA_SEAL)
          ),
          type: 'note'
        }
      )

      show_block_4.append(
        {
          display: shake(items: vortex_list.map(&:display_name),
                         type: Vortex::NAME),
          type: 'note'
        }
      )

      show_block_4.append(
        { 
          display: spin_down(
            items: [plate_display],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: temporary_options[:centrifuge_parameters][:time]
          ),
          type: 'note'
        }
      )

      show_block_4.append(
        { 
          display: place_on_magnet(plate_display),
          type: 'note'
        }
      )

      display_hash(title: 'Perform the following steps',
                   hash_to_show: show_block_1)
      display_hash(title: 'Perform the following steps',
                   hash_to_show: show_block_2)
      display_hash(title: 'Perform the following steps',
                   hash_to_show: show_block_3)
      display_hash(title: 'Perform the following steps',
                   hash_to_show: show_block_4)
      run_qpcr(op: op,
               plates: [plate])
    end

    {}

  end

  def set_up_test(op)
    sample = op.input(POOLED_PLATE).part.sample
    plate = op.input(POOLED_PLATE).collection
    samples = Array.new(plate.get_empty.length, sample)
    plate.add_samples(samples)
  end

end
