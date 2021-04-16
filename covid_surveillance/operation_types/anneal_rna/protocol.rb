# typed: false
# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Standard Libs/Units'
needs 'Standard Libs/CommonInputOutputNames'

needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Covid Surveillance/CovidSurveillanceHelper'

needs 'Liquid Robot Helper/RobotHelper'

needs 'Composition Libs/Composition'
needs 'Composition Libs/CompositionHelper'

needs 'Collection Management/CollectionActions'
needs 'Collection Management/CollectionTransfer'

needs 'PCR Protocols/RunThermocycler'

needs 'Container/ItemContainer'
needs 'Container/KitHelper'
needs 'Kits/KitContents'

needs 'Consumable Libs/Consumables'

needs 'Consumable Libs/ConsumableDefinitions'


class Protocol
  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper
  include CommonInputOutputNames
  include CompositionHelper
  include CollectionActions
  include CollectionTransfer
  include RunThermocycler
  include KitHelper
  include CovidSurveillanceHelper
  include KitContents
  include ConsumableDefinitions

############ Composition Parts ###########
  ANNEAL_KIT = 'Anneal RNA Kit'
  CDNA_PLATE = 'CDNA Sample Plate'
  POOLED_PLATE = 'RNA Sample Plate'
  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: 8.5, units: MICROLITERS,
         sample_name: 'Pooled Specimens'
       },
       {
         input_name: CDNA_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: 'Pooled Specimens'
       }
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[AREA_SEAL],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[PLATE_384_WELL],
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
    mosquito_robot_program: 'Anneal RNA and FS Synthesis',
    mosquito_robot_model: Mosquito::MODEL,
    dragonfly_robot_program: 'EP3_HT',
    dragonfly_robot_model: Dragonfly::MODEL,
    thermocycler_model: TestThermocycler::MODEL,
    program_name: 'duke_anneal_rna',
    qpcr: true,
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                        speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                            speed: create_qty(qty: 1000, units: TIMES_G) }
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

      temporary_options = op.temporary[:options]

      plate = op.input(POOLED_PLATE).collection

      required_reactions = create_qty(qty: plate.parts.length,
                                      units: 'rxn')

      composition, consumables, kits = setup_kit_composition(
        kit_sample_names: [ANNEAL_KIT],
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumable_data
      )

      kit = kits.first

      composition.set_adj_qty(plate.get_non_empty.length,
                              extra: 0.005)

      composition.input(POOLED_PLATE).item = plate

      op.output(CDNA_PLATE).make_collection
      cdna = op.output(CDNA_PLATE).collection
      composition.input(CDNA_PLATE).item = cdna

      cdna_display = composition.input(CDNA_PLATE).display_name
      plate_display = composition.input(POOLED_PLATE).display_name

      retrieve_items = reject_components(
        list_of_rejections: [POOLED_PLATE, CDNA_PLATE],
        components: composition.components
      )

      # SHOW gets the parts in the composition
      display(
        title: 'Retrieve Materials',
        show_block: retrieve_materials(
          retrieve_items + consumables.consumables,
          volume_table: true,
          adj_qty: true
        )
      )

      # Form a show block array
      show_block_1a = []
      show_block_1a.append(get_and_label_new_item(composition.input(CDNA_PLATE)))

      show_block_1b = shake(
        items: retrieve_items.map(&:display_name),
        type: Vortex::NAME
      )

      display_hash(
        title: 'Prepare Samples and Reagents',
        hash_to_show: [show_block_1a.flatten,
                       show_block_1b.flatten]
      )

      drgprogram = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:dragonfly_robot_program]
      )

      drgrobot = LiquidRobotFactory.build(
        model: temporary_options[:dragonfly_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      display_hash(
        title: 'Set Up and Run Robot',
        hash_to_show: use_robot(
          program: drgprogram,
          robot: drgrobot,
          items: [composition.input(EPH3_HT).display_name,
                  cdna_display]
        )
      )

      program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:mosquito_robot_program]
      )

      robot = LiquidRobotFactory.build(
        model: temporary_options[:mosquito_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      display_hash(
        title: 'Setup and Run Robot',
        hash_to_show: use_robot(
          program: program,
          robot: robot, items: [plate_display, cdna_display]
        )
      )

      association_map = one_to_one_association_map(from_collection: plate)
      copy_wells(from_collection: plate,
                 to_collection: cdna,
                 association_map: association_map)

      associate_transfer_collection_to_collection(
        from_collection: plate,
        to_collection: cdna,
        association_map: association_map,
        transfer_vol: composition.input(POOLED_PLATE).qty
      )

      associate_transfer_item_to_collection(
        from_item: composition.input('EPH3 HT').item,
        to_collection: cdna,
        association_map: association_map,
        transfer_vol: composition.input('EPH3 HT').qty
      )

      kit.remove_volume(required_reactions)

      show_block_3a = []
      show_block_3a.append(
        seal_plate(
          [cdna_display],
          seal: consumables.input(AREA_SEAL)
        )
      )

      show_block_3b = []
      show_block_3b.append(
        shake(
          items: [cdna_display],
          speed: temporary_options[:shaker_parameters][:speed],
          time: temporary_options[:shaker_parameters][:time]
        )
      )

      show_block_3c = []
      show_block_3c.append(
        spin_down(
          items: [cdna_display],
          speed: temporary_options[:centrifuge_parameters][:speed],
          time: temporary_options[:centrifuge_parameters][:time]
        )
      )

      display_hash(
        title: 'Prepare for Thermocycler',
        hash_to_show: [show_block_3a.flatten,
                       show_block_3b.flatten,
                       show_block_3c.flatten]
      )

      run_qpcr(op: op,
               plates: [composition.input(CDNA_PLATE)])
    end

    {}

  end

  def set_up_test(op)
    sample = op.input(POOLED_PLATE).part.sample
    plate = op.input(POOLED_PLATE).collection
    samples = Array.new(plate.get_non_empty.length, sample)
    plate.add_samples(samples)
  end

end
