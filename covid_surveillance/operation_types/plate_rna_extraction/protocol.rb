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
needs 'Liquid Robot Helper/RobotHelper'

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'Container/KitHelper'
needs 'Kits/KitContents'

needs 'ConsumableLibs/Consumables'
needs 'ConsumableLibs/ConsumableDefinitions'

needs 'Covid Surveillance/CovidSurveillanceHelper'


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
  include KitHelper
  include KitContents
  include CovidSurveillanceHelper


  # ============= Composition Definitions ==============#
  EXTRACTION_KIT = 'QiAmp 96 Viral RNA Kit'

  ETHANOL = 'Absolute ethanol'

  AVL_AVE_CARRIER = 'Mixed Carrier RNA, AVE, AVL'

  EXTRACTION_PLATE = 'Extracted Sample Plate'

  def components
    [
       {
         input_name: POOLED_PLATE,
         qty: 140, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: '96-Well Plate'
       },
       {
         input_name: ETHANOL,
         qty: 560, units: MICROLITERS,
         sample_name: ETHANOL,
         object_type: 'Reagent Bottle'
       },
       {
        input_name: AVL_AVE_CARRIER,
        qty: 560, units: MICROLITERS,
        sample_name: AVL_AVE_CARRIER,
        object_type: 'Reagent Bottle'
      },
      {
        input_name: EXTRACTION_PLATE,
        qty: nil, units: nil,
        sample_name: 'Pooled Specimens',
        object_type: '96-Well Plate'
      },
      {
        input_name: DEEP_PLATE_96_WELL,
        qty: 630, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        object_type: DEEP_PLATE_96_WELL
      },
      {
        input_name: QIAAMP_PLATE,
        qty: nil, units: nil,
        sample_name: 'Pooled Specimens',
        object_type: QIAAMP_PLATE
      },
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[DEEP_PLATE_96_WELL],
        qty: 2, units: 'Each'
      },
      {
        consumable: CONSUMABLES[PLATE_96_WELL],
        qty: 2, units: 'Each'
      },
      {
        consumable: CONSUMABLES[TAPE_PAD],
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
      centrifuge_parameters: { time: create_qty(qty: 4, units: MINUTES),
                               speed: create_qty(qty: 5788, units: TIMES_G) },
      incubation_params: { time: create_qty(qty: 10, units: MINUTES),
                           temperature: create_qty(qty: 'room temperature',
                                                   units: '') }
    }
  end

  # Default parameters that are applied to individual operations.
  #   Can be overridden by:
  #   * Adding a JSON-formatted list of key, value pairs to an `Operation`
  #     input of type JSON and named `Options`.
  #
  def default_operation_params
    {
    }
  end

  ########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    operations.make
    set_up_test(operations) if debug

    required_reactions = get_number_of_required_reactions(operations)

    operations.each do |op|
      op.temporary[:composition] = setup_kit_composition(
        kit_sample_name: EXTRACTION_KIT,
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumable_data
      )

      op.temporary[:composition].first.input(POOLED_PLATE).item =
        op.input(POOLED_PLATE).collection
    end

    prep_carrier_rna(operations: operations)

    dilute_buffer(operations: operations, input: AW1)

    dilute_buffer(operations: operations, input: AW2)

    copy_and_add_item_to_all(operations: operations,
                             to_name: DEEP_PLATE_96_WELL,
                             from_name: POOLED_PLATE,
                             from_item: AVL_AVE_CARRIER)

    seal_plate(operations.map{ |op| op.temporary[:composition].first.input(DEEP_PLATE_96_WELL).item },
               seal: operations.first.temporary[:composition][1].input(TAPE_PAD))

    show_incubate_items(
      items: operations.map { |op| op.temporary[:composition].first.input(DEEP_PLATE_96_WELL).item },
      time: { qty: 10, units: MINUTES },
      temperature: default_job_params[:incubation_params][:temperature]
    )

    add_item_to_all(operations: operations,
                    to_name: DEEP_PLATE_96_WELL,
                    from_name: ETHANOL)

    2.times do 
      copy_and_add_item_to_all(operations: operations,
                              to_name: QIAAMP_PLATE,
                              from_name: DEEP_PLATE_96_WELL,
                              sblock: true)

      seal_plate(operations.map{ |op| op.temporary[:composition].first.input(QIAAMP_PLATE).item },
                 seal: operations.first.temporary[:composition][1].input(TAPE_PAD).input_name)

      spin_down(
        items: operations.map{ |op| op.temporary[:composition].first.input(QIAAMP_PLATE).item},
        speed: default_job_params[:centrifuge_parameters][:speed],
        time: { qty: 4, units: MINUTES },
        type: 'QIAGEN 4-16KS Centrifuge'
      )
    end

    place_on_sblock(operations, QIAAMP_PLATE)

    add_item_to_all(operations: operations, to_name: QIAAMP_PLATE, from_name: AW1)

    seal_plate(operations.map{ |op| op.temporary[:composition].first.input(QIAAMP_PLATE).item },
               seal: operations.first.temporary[:composition][1].input(TAPE_PAD).input_name)

    spin_down(
      items: operations.map{ |op| op.temporary[:composition].first.input(QIAAMP_PLATE).item },
      speed: default_job_params[:centrifuge_parameters][:speed],
      time: { qty: 4, units: MINUTES },
      type: 'QIAGEN 4-16KS Centrifuge'
    )

    add_item_to_all(operations: operations, to_name: QIAAMP_PLATE, from_name: ETHANOL)

    seal_plate(operations.map{ |op| op.temporary[:composition].first.input(QIAAMP_PLATE).item },
               seal: operations.first.temporary[:composition][1].input(TAPE_PAD).input_name)

    spin_down(
      items: operations.map{ |op| op.temporary[:composition].first.input(QIAAMP_PLATE).item },
      speed: default_job_params[:centrifuge_parameters][:speed],
      time: { qty: 5, units: MINUTES },
      type: 'QIAGEN 4-16KS Centrifuge'
    )

    place_on_sblock(operations, QIAAMP_PLATE)

    spin_down(
      items: operations.map{ |op| op.temporary[:composition].first.input(QIAAMP_PLATE).item },
      speed: default_job_params[:centrifuge_parameters][:speed],
      time: { qty: 10, units: MINUTES },
      type: 'QIAGEN 4-16KS Centrifuge'
    )

    tab = [['QIAamp 96 Plate ID', 'Clean Elution Plate ID']]
    operations.each do |op|
      composition = op.temporary[:composition].first

      extraction_comp = composition.input(EXTRACTION_PLATE)
      extraction_comp.item = get_and_label_new_plate(op.output(EXTRACTION_PLATE).collection)
      from_comp = composition.input(QIAAMP_PLATE)
      map = one_to_one_association_map(from_collection: from_comp.item)
      copy_wells(from_collection: from_comp.item,
                 to_collection: extraction_comp.item,
                 association_map: map)
      tab.append([from_comp.item.to_s, extraction_comp.item.to_s])
    end

    show do
      title 'Place QIAamp 96 Plate on Elution Plate'
      note 'Please place each QIAamp 96 Plate on a clean Elution Plate'
      table tab
    end

    add_item_to_all(operations: operations, to_name: QIAAMP_PLATE, from_name: AVE)

    spin_down(
      items: operations.map{ |op| op.temporary[:composition].first.input(QIAAMP_PLATE).item },
      speed: default_job_params[:centrifuge_parameters][:speed],
      time: { qty: 4, units: MINUTES },
      type: 'QIAGEN 4-16KS Centrifuge'
    )

    seal_plate(operations.map{ |op| op.temporary[:composition].first.input(QIAAMP_PLATE).item },
               seal: operations.first.temporary[:composition][1].input(TAPE_PAD).input_name)

    {}
  end

  # determins the total number of reactions required for job
  # @param operations [OperationList] list of operations
  #
  # @return [Int] numer of reactions required for job
  def get_number_of_required_reactions(operations)
    num = 0
    operations.each do |op|
      num += op.input(POOLED_PLATE).collection.get_non_empty.length
    end
    num
  end

  def add_item_to_all(operations:, to_name:, from_name:)
    operations.each do |op|
      composition, = op.temporary[:composition].first
      map = one_to_one_association_map(from_collection: composition.input(to_name).item)
      source = composition.input(from_name)
      source = composition.input(EXTRACTION_KIT).input(from_name) unless source.present?

      destination = composition.input(to_name)
      destination = composition.input(to_name) unless destination.present?

      multichannel_item_to_collection(
        source: source.item,
        to_collection: destination.item,
        association_map: map,
        volume: source.volume_hash
      )
    end
  end

  def copy_and_add_item_to_all(operations:, to_name:, from_name:,
                               from_item: nil, sblock: false)
    operations.each do |op|
      composition, consumables, _kit_ = op.temporary[:composition]

      deep_plate = composition.input(to_name)
      plate_object_type = ObjectType.find(consumables.input(DEEP_PLATE_96_WELL))

      deep_plate.item = make_new_plate(plate_object_type)
      place_on_sblock([op], to_name) if sblock
      input_plate = composition.input(from_name).item
      map = one_to_one_association_map(from_collection: input_plate)
      copy_wells(from_collection: input_plate,
                 to_collection: deep_plate.item,
                 association_map: map)
      if from_item.present?
        multichannel_item_to_collection(
          source: composition.input(from_item).item,
          to_collection: deep_plate.item,
          association_map: map,
          volume: composition.input(from_item).volume_hash
        )
      end

      multichannel_collection_to_collection(
        from_collection: input_plate,
        to_collection: deep_plate.item,
        association_map: map,
        volume: composition.input(from_name).volume_hash
      )
    end
  end

  def place_on_sblock(ops, comp_name)
    show do
      title "Place on #{ops.first.temporary[:composition][1].input(DEEP_PLATE_96_WELL) }"
      ops.each do |op|
        comp. consumable, _kit_ = op.temporary[:composition]
        note "Place <b>#{comp.input(comp_name).item}</b> on a new <b>#{consumable.input(DEEP_PLATE_96_WELL)}</b>"
      end
    end
  end

  # Directions to dilute buffers
  #
  # @param 
  def dilute_buffer(operations:, input:)
    operations.each do |op|
      comp = op.temporary[:composition].first
      component = comp.input(input)
      ethanol = comp.input(ETHANOL)
      show do
        title 'Dilute Buffer Concentrate'
        note "Add appropriate amount of ethanol <b>#{ethanol.item}</b> to <b>#{component.input_name} #{component.item}</b>"
      end
    end
  end

  # directions to prep the carrier RNA
  #
  # @param operations [OperationList] list of operations
  def prep_carrier_rna(operations:)
    operations.each do |op|
      composition = op.temporary[:composition].first
      num_samples = composition.input(POOLED_PLATE).item.get_non_empty.length
      composition.input(AVE).adj_qty = 1550 # TODO Encode this somewhere not hard coded

      mix = composition.input(AVL_AVE_CARRIER)
      avl = composition.input(AVL)
      carrier = composition.input(AVL)

      create_master_mix(components: [composition.input(AVE)],
                        master_mix: carrier,
                        adj_qty: true)

      mix.item = make_item(
        sample: mix.sample,
        object_type: mix.object_type
      )

      avl.adj_qty = num_samples * 600
      carrier.adjusted_qty(num_samples)

      create_master_mix(components: [avl, carrier],
                        master_mix: mix,
                        adj_qty: true,
                        vortex: false)
      show do
        title 'Mix by Inversion'
        note "Gently mix #{mix.item} by inverting tube 10 times"
      end
    end
  end

  def set_up_test(operations)
    operations.each do |op|
      sample = op.input(POOLED_PLATE).part.sample
      plate = op.input(POOLED_PLATE).collection
      samples = Array.new(20, sample)
      plate.add_samples(samples)
    end
  end
end
