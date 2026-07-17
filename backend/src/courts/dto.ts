import {
  IsArray,
  IsBoolean,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class ProposeCourtDto {
  @IsString() name!: string;
  @IsOptional() @IsString() area?: string;
  @IsOptional() @IsString() dist?: string;
  @IsOptional() @IsString() img?: string;
  @IsOptional() @IsString() type?: string;
  @IsOptional() @IsBoolean() free?: boolean;
  @IsOptional() @IsBoolean() lit?: boolean;
  @IsOptional() @IsNumber() hoops?: number;
  @IsOptional() @IsString() surface?: string;
  @IsOptional() @IsString() vibe?: string;
  @IsOptional() @IsString() hours?: string;
  @IsOptional() @IsString() openTime?: string;
  @IsOptional() @IsString() closeTime?: string;
  @IsOptional() @IsArray() @IsString({ each: true }) badges?: string[];
  @IsOptional() @IsString() desc?: string;
  @IsOptional() @IsNumber() lat?: number;
  @IsOptional() @IsNumber() lng?: number;
}

export class AddReviewDto {
  @IsNumber() @Min(1) @Max(5) rating!: number;
  @IsString() comment!: string;
}
